# API-Billed Auto-Run Decisions, Cache Keep-Warm and agy Hydrogen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In an auto run, planning choices go first to OpenAI's Decisions API and `judge-opus` rulings go first to a judge billed to a developer API budget; outside an auto run the cockpit keeps the prompt cache warm during long background waits; and Gemini 4 Hydrogen is measured against Argon and placed in the agy roster by a fixed rule.

**Architecture:** Verify the two judge CLIs first, then build bottom-up: the budget library and spend file, `scripts/decide`, `scripts/run-api-judge` in two tasks (the chain, then key hygiene and charging), and only then point the ladder's prose at them. The cockpit keep-warm and the Hydrogen measurement are independent of the rest and come after. A last task makes the live, billed checks and writes the user-facing docs.

**Tech Stack:** Bash scripts and bash test suites, Node (`.mjs`) helpers and config schema, TypeScript cockpit mod and its tests, Markdown references and skills.

**Spec:** docs/dforge/specs/2026-11-14-api-decisions-keep-warm-hydrogen-design.md

**Execution:** inline — `claude --model opus --effort high` — Task 6 totals 8 with risk 3

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-14 — dforge:judge-opus — executability 14 / coherence 15 / coverage 16 / assumptions 15 (round 1)

## Global Constraints

- The run works in place: in `/root/repositories/darkraise-ai-plugins` on a new branch created from `main` at execution setup. Nothing is pushed; finishing merges into local `main`.
- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind. No task edits a `"version"` line: `scripts/release.mjs` derives the version from the commit types, and a `feat(dforge):` commit gives the next minor.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Do not edit historical docs (`docs/dforge/plans/*`, `docs/dforge/specs/*`, `docs/dforge/notes/*`, `docs/dforge/registers/*`) other than this plan, its spec, its register and the notes this plan creates.
- Every test, suite and CLI command runs under `timeout`. Run one plugin suite as `timeout 600 bash plugins/dforge/tests/<name>.test.sh [part…]`. Call the Claude CLI as `/root/.local/bin/claude`: `claude` is a shell function in the tool shell.
- Every process a task starts (a stub HTTP server, a background CLI) is stopped by that task's test before it exits; a test kills only PIDs it started.
- Key values: dforge reads only `DFORGE_OPENAI_API_KEY`, `DFORGE_ANTHROPIC_API_KEY` and `DFORGE_AGENTROUTER_API_KEY`. No script prints, logs or writes a key value, and no test puts a real key in a file. Tests use the sentinel values `sk-test-openai-SENTINEL`, `sk-test-anthropic-SENTINEL` and `sk-test-agentrouter-SENTINEL`.
- Billed calls happen only in Task 1 and Task 10 (the three API keys, a few calls each) and Task 9 (ten agy Gemini review runs). Every other test uses stubs. No run names a Claude model through agy, and no Codex or agy run passes `--dangerously-skip-permissions`. Codex runs remain one at a time per machine.
- A harness measurement never touches the real checkout: Task 9's agy runs work in a scratch clone under the session's scratch directory.
- A new suite under `plugins/dforge/tests/` gets a `windowsSeconds` weight in `scripts/test-shards.mjs` in the task that creates it.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`, `node.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset) — convert the path with `cygpath -m` before the call (`dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches — normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep — pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes — pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails — import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process — create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running — run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **C1 key variables and budget ids.** Budget ids are `anthropic`, `openai`, `agentrouter`. Key variable per id: `DFORGE_ANTHROPIC_API_KEY`, `DFORGE_OPENAI_API_KEY`, `DFORGE_AGENTROUTER_API_KEY`. Cap setting per id: `apiBudgetAnthropic`, `apiBudgetOpenai`, `apiBudgetAgentRouter`.
- **C2 settings** (`plugins/dforge/config/schema.mjs`, all `target: 'dforge'`; the five Workflow keys directly after `agyReview`, `keepWarm` directly after `autoCompactEnabled`): `decisionApi` enum `off|shadow|on`, default `off`, `enforcedBy: 'script'`, group Workflow; `decisionConfidence` number 50 to 99, step 1, unit `%`, default 85, `enforcedBy: 'script'`, group Workflow; `apiBudgetAnthropic`, `apiBudgetOpenai`, `apiBudgetAgentRouter` numbers 0 to 1000, step 5, default 0, `zero: 'off'`, `enforcedBy: 'script'`, group Workflow; `keepWarm` number 0 to 59, step 1, unit `min`, default 50 (0 on the `off` outcome of Task 8's draft check), `zero: 'off'`, group Context, read by the cockpit. The `apiBudgetAgentRouter` description contains the sentence `A cap above 0 sends ruling prompts, and any file its judge reads, to AgentRouter, a third party.`
- **C3 spend file.** `~/.dforge/api-spend.json`, overridden by `DFORGE_API_SPEND_FILE`: `{"<id>": {"spent_usd": <number>, "calls": <integer>}}`, a missing id counting as zero. Amounts are printed with four decimal places.
- **C4 `scripts/api-spend`.** `api-spend status` prints, in the order `anthropic`, `openai`, `agentrouter`, one line each: `api-budget <id> open=<true|false> spent=<usd> cap=<usd> reason=<ok|off|no-key|spent>` (`off`: cap 0; `no-key`: cap above 0 and the key variable empty or unset; `spent`: `spent_usd >= 0.95 * cap`; checked in that order). `api-spend add <id> <usd>` adds `<usd>` to `spent_usd`, adds 1 to `calls`, prints nothing and exits 0. Exit 2 on a usage error or an unknown id, exit 1 when the file's lock could not be had.
- **C5 `scripts/lib/api-budget.sh`** (sourced): `api_budget_key_var <id>` prints the variable name; `api_budget_state <id>` prints the C4 line for one id and returns 0 when open, 1 when closed; `api_budget_price <model> <input|cached_input|output>` prints the USD price per million tokens from the price table, or returns 1 when the model or field is missing; `api_budget_charge <id> <usd>` runs the C4 `add` and returns its status. A caller whose charge fails prints `<script>: the charge to <id> was not recorded` on stderr and changes nothing else: its outcome, its status line and its exit code stand.
- **C6 price table.** `plugins/dforge/reference/api-prices.json`, overridden by `DFORGE_API_PRICES`: `{"checked": "<YYYY-MM-DD>", "models": {"<model>": {"source": "<url>", "input": <usd per million>, "cached_input": <usd per million>, "output": <usd per million>}}}`.
- **C7 `scripts/decide`.** `decide ask --id <id> --question <q> --options "<a | b | …>" [--evidence <file>]...`; `decide record --id <id> --ruling <choice>`; `decide report`. `ask` prints exactly one line, `ruling: <choice> — Decisions API (confidence <c>)` (exit 0, `<c>` the lower confidence with two decimals) or `no ruling reason=<token>` (exit 3), token one of `off`, `shadow`, `no-run`, `closed`, `disagree`, `low-confidence`, `needs-more`, `guarded`, `refusal`, `evidence`, `error`. Exit 2 is a usage error. Env seams: `DFORGE_DECISIONS_URL` (default `https://api.openai.com/v1/decisions`), `DFORGE_DECISIONS_TIMEOUT` seconds (default 30). Question names sent: `ruling`, `ruling_reversed`, `needs_more`, `guarded`. Choice values sent: `option_<i>` for the i-th option as given (from 1), the same value for the same option in both questions, and `other` last in both; the printed and logged choice is the option's text. A confidence is a fraction from 0 to 1 and rules when it is at least `decisionConfidence / 100`. Limits: `needs_more <= 0.15`, `guarded <= 0.10`, evidence at most 400000 bytes.
- **C8 decisions log.** `<state>/decisions.jsonl`, one JSON object per line. An ask line: `{"kind":"ask","id":…,"options":[…],"mode":"shadow|on","outcome":"<ruled|token>","choice":…,"choice_reversed":…,"confidence":…,"confidence_reversed":…,"needs_more":…,"guarded":…}` with the six answer fields `null` when no request was answered; `choice` and `choice_reversed` hold the option's text or `other`, and `outcome` is what the answer would rule (`ruled` or a C7 token other than `off` and `shadow`) in either mode. A record line: `{"kind":"record","id":…,"ruling":…}`. `decide report` prints one `band <lo>-<hi>: <n> recorded, <m> match` line per band (`50-59`, `60-69`, `70-79`, `80-89`, `90-100`, by the ask's lower confidence in percent) and a last line `promote: yes` or `promote: no (<n> recorded, <p>% match)`, counting only asks at or above `decisionConfidence` whose id has a record line.
- **C9 `api-judge` block** (`plugins/dforge/reference/ladder.md`, below `agy-judge`), rows `budget model effort seconds`, in the order tried: `anthropic claude-opus-5-5 medium 1800`, `openai gpt-6-astra xhigh 1800`, `agentrouter gpt-6-astra xhigh 1800`, less the rows of a CLI that the `## Results` section of Task 1's note records as disproved (`anthropic` for the Claude CLI; `openai` and `agentrouter` together for the Codex CLI).
- **C10 `scripts/run-api-judge`.** `run-api-judge --prompt <file> --report <file> --cwd <dir> [--add-dir <dir>]... [--dry-run]`. Lines on stdout, each also appended to `<state>/api-judge.log`: `api-judge <budget>:<model>/<effort> started`; `api-judge <budget> running <seconds>s`; and per budget tried `api-judge <budget>:<model>/<effort> status=<OK|FAILED|TIMEOUT|SKIPPED> exit=<n> out=<path|-> spent=<usd> reason=<token>`, token `none` (OK), `off`, `no-key`, `spent`, `no-price` (SKIPPED), `error`, `no-verdict`, `wrote`, `key-in-reply` (FAILED), `timeout` (TIMEOUT). With no run bound it prints `api-judge none status=SKIPPED exit=3 out=- spent=0.0000 reason=no-run`. Exit 0 a report was written; 3 none was; 2 usage. Env seams: `API_JUDGE_LADDER` (default `reference/ladder.md`), `API_JUDGE_BEAT` seconds between `running` lines (default 300), `API_JUDGE_CHAIN` seconds for the whole chain (default 2400), `API_JUDGE_CLAUDE` and `API_JUDGE_CODEX` (the CLI commands; by default `claude` on PATH, else `$HOME/.local/bin/claude`, and `codex`). A `SKIPPED` line carries `exit=0`, a `TIMEOUT` line `exit=124`, and `out=` is the `--report` path on `OK` and `-` otherwise. `spent=` is what that run was charged, with four decimals; a run that reported neither cost nor tokens is charged `1.0000`. `--dry-run` prints `api-judge <budget>:<model>/<effort> dry-run: <command line>` for each open row, with the key shown as `$<variable name>`, and starts nothing. The Codex provider's `env_key` is `DFORGE_JUDGE_KEY`; the Anthropic child reads `ANTHROPIC_API_KEY`.
- **C11 judge CLI command lines.** The exact `claude --bare -p` and `codex exec` invocations are the ones Task 1 records in `docs/dforge/notes/2026-11-14-api-judge-cli-check.md` under the headings `## Anthropic command`, `## Codex command` and `## Cost and usage fields`. Whatever else the note records, the Anthropic line carries `--bare`, `--tools Read,Grep,Glob` and `--model <the row's model>`, each Codex line carries `--sandbox read-only`, and no line carries `--dangerously-skip-permissions`, `workspace-write` or `danger-full-access`.
- **C12 keep-warm.** Prompt text, exactly: `Keep-warm: background work is still running and the prompt cache is about to expire. Reply with the single line \`Still waiting.\` and end the turn. Start nothing and call no tool.` At most 6 in a row (`KEEP_WARM_CAP`).
- **C13 Hydrogen note.** `docs/dforge/notes/2026-11-14-agy-hydrogen-review.md` holds a line `agy version: <x.y.z>` and ends with the line `Verdict: <model> <effort>`, `<model>` either `gemini-4-hydrogen` or `gemini-4-argon`.

## Assumptions (evidence)

- `claude --help` (run 2026-11-14) describes `--bare` as using "strictly ANTHROPIC_API_KEY or apiKeyHelper via --settings (OAuth and keychain never read)" and lists `--add-dir`, `--json-schema`, `--print` and `--output-format`. That a bare print run reports its cost in its JSON output: unverified — Task 1 verifies it.
- `claude --help` (run 2026-11-14): `--tools <tools...>` "Specify the list of available tools from the built-in set … or specify tool names (e.g. "Bash,Edit,Read")", and `--effort <level>` (low, medium, high, xhigh, max).
- `codex exec --help` (codex-cli 0.163.0, run 2026-11-14) lists `-c <key=value>`, `-m`, `--output-schema`, `--json`, `-o, --output-last-message <FILE>`, `--skip-git-repo-check` and `-s, --sandbox <SANDBOX_MODE>` with the values `read-only`, `workspace-write` and `danger-full-access`. That a provider given by `-c` overrides with an `env_key`, in a `CODEX_HOME` of its own, runs on the key and leaves the user's login untouched, and that `--json` streams token usage: unverified — Task 1 verifies it.
- The spec's riskiest assumption reads "unverified — the plan's first task verifies it"; Task 1 is that step. If Task 1 disproves it for a CLI, that budget's row leaves the `api-judge` block (C9), its register row is deferred, and no raw-HTTP judge is built.
- OpenAI's Decisions API: `POST /v1/decisions`, model `gpt-6-luna`, `predicate`, `choice` and `score` questions, $0.10 per million input tokens, no output charge (https://developers.openai.com/api/docs/guides/decisions, read 2026-11-14).
- The Decisions API identifies a question by `name` and takes its text as `instructions`; a response's `answers` carry `name` and `type`, a choice answer `choice`, `probabilities` and `confidence`, a predicate answer `probability` from 0 to 1, a refused one `type: "refusal"`, and the charge is read from `usage.input_tokens` (the same guide, re-read 2026-11-14). The guide gives no range for `confidence`; its examples are fractions (0.93, 0.55), and C7 treats it as one.
- The stub CLIs of Task 5 print the shapes the CLIs' documentation describes: `result` and `total_cost_usd` in the one JSON object of `claude -p --output-format json`, and in `codex exec --json` an `item.completed` agent message and a `turn.completed` line with `usage.input_tokens`, `usage.cached_input_tokens` and `usage.output_tokens`. Unverified — Task 1 verifies it, and Task 5 Step 1 changes the stubs to what Task 1's note records.
- The spec lists the plugin version among the changed files. `scripts/release.mjs` writes it at release from the commit types (`scripts/release.mjs:29-33`), so the `feat(dforge):` commits of this plan are what change it.
- `agy models` on agy 1.5.7 lists `gemini-4-hydrogen` at low, medium, high and xhigh and `gemini-4-argon` at low, medium and high (run 2026-11-14).
- `scripts/run-agy-review.sh` reads its roster from `AGY_REVIEW_LADDER` (`plugins/dforge/scripts/run-agy-review.sh:15`), so a fixture ladder with one row runs one model without editing `reference/ladder.md`.
- Main sessions write the one-hour cache: the eight newest transcripts of 2026-11-14 hold only `ephemeral_1h_input_tokens` writes.
- The cockpit submits its own prompts with `$.prompt.submit({ text, asUser: true })` and its watchdog ticks every 60 s (`plugins/dforge/hooks/cockpit/register.tsx`, `watchdogTick`, `reconcileBackground`). Whether a submit disturbs a half-typed composer: unverified — Task 8 verifies it first.
- The full suite last passed in 328 s (`.dforge/suites.tsv`), above 300 s, and the project has no `gates.md` and no impact-selection runner, so the Task check is rule 4.
- No task edits a version line: `scripts/release.mjs` bumps the version from pending commit subjects (`scripts/release.mjs:29-33`).

## Task index

1. Verify the judge CLIs on API keys
2. Settings, budgets and the spend file
3. `decide ask`: the Decisions API rung
4. `decide record` and `decide report`
5. `run-api-judge`: roster, chain and status lines
6. `run-api-judge`: key hygiene, worktree proof and charging
7. Point the auto-run ladder at the new rungs
8. Cockpit keep-warm
9. Measure Hydrogen and place it in the agy roster
10. Live checks and user-facing docs

---

### Task 1: Verify the judge CLIs on API keys

**Files:**
- Create: `docs/dforge/notes/2026-11-14-api-judge-cli-check.md`

**Interfaces:**
- Consumes: nothing.
- Produces: C11, the command lines and the cost and usage fields Tasks 5 and 6 build on.

**Items:** 4, 5
**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 1 - coupling 0 - risk 1 = 2

- [ ] **Step 1: No new test, because this task writes a note no script reads; the command lines it records are exercised by Task 5's test `plugins/dforge/tests/api-judge.test.sh::first open budget wins` and Task 10's live checks**

- [ ] **Step 2: Read the flags**

Run `timeout 20 /root/.local/bin/claude --help` and `timeout 20 codex exec --help`, and `timeout 20 codex --help`. Find, and copy the help line of each into the note: for `claude`, `--bare`, `--print`, `--output-format`, `--model`, `--add-dir`, `--tools` (it sets the list of available tools, here `Read,Grep,Glob`; `--allowed-tools` only pre-approves tools and is not the restriction), and `--effort`; for `codex exec`, `-c`, `-m`, `--json`, `--output-last-message`, `--sandbox` and its `read-only` value, and `--skip-git-repo-check`. A flag the help no longer lists is recorded as missing, with the flag that replaced it.

- [ ] **Step 3: Prove the key path without a key**

In a scratch directory holding one file `README.md` with the text `hello`:

1. Run the Anthropic command with a deliberately invalid key in the child's environment only, every `DFORGE_*_API_KEY` and vendor key variable removed first:
   `env -u DFORGE_OPENAI_API_KEY -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_AGENTROUTER_API_KEY -u OPENAI_API_KEY ANTHROPIC_API_KEY=sk-invalid timeout 60 /root/.local/bin/claude --bare -p "Reply with the word ok." --output-format json` plus the tool and model flags found in Step 2. Expected: it fails with an authentication error. A successful answer means bare mode fell back to the subscription login: record that, and the Anthropic budget's row leaves C9 as the Assumptions say.
2. Run the Codex command the same way: a fresh empty directory as `CODEX_HOME`, the provider given only by `-c` overrides (`model_provider="dforge"`, `model_providers.dforge.name`, `.base_url="https://api.openai.com/v1"`, `.env_key="DFORGE_JUDGE_KEY"`, `.wire_api="responses"`), `DFORGE_JUDGE_KEY=sk-invalid` in the child's environment, the read-only sandbox, `--json`. Expected: an authentication error from the API, and `sha256sum ~/.codex/auth.json` unchanged before and after. A successful answer means it used the subscription login: record that, and both Codex rows leave C9.

- [ ] **Step 4: Run each CLI on its real key, when the key is set**

For each of the three key variables that is set and non-empty, run the same command with the real key passed into the child's environment only (for AgentRouter the base URL is `https://agentrouter.org/v1`), with the prompt `Read README.md and reply with its first word only.`, model and effort from C9. Record for each: whether the reply was `hello`, the JSON field that holds the reply text, the field or event that holds the cost (Anthropic) or the token counts (Codex: input, cached input, output), and the wall time. Never write a key value into the note or the transcript: refer to the variables by name. A variable that is not set is recorded as `not run — <VARIABLE> unset`, and Task 10 repeats this step.

- [ ] **Step 5: Write the note**

Write `docs/dforge/notes/2026-11-14-api-judge-cli-check.md` with these headings: `## Anthropic command` (the full command line, with `<prompt>`, `<cwd>` and `<add-dir>` placeholders and the key shown as `$DFORGE_ANTHROPIC_API_KEY`), `## Codex command` (the same for `codex exec`, the base URL and key variable as parameters), `## Cost and usage fields` (the JSON paths found in Step 4, or `unverified — no key was set` with the documentation line that names them), `## Results` (one line per budget: verified live, verified to the authentication error only, or disproved).

- [ ] **Step 6: Commit**

```bash
git add docs/dforge/notes/2026-11-14-api-judge-cli-check.md
git commit -m "docs(dforge): record the API judge CLI check"
```

### Task 2: Settings, budgets and the spend file

**Files:**
- Modify: `plugins/dforge/config/schema.mjs` (five entries directly after `agyReview`, one after `autoCompactEnabled`)
- Create: `plugins/dforge/scripts/lib/api-budget.sh`
- Create: `plugins/dforge/scripts/api-spend`
- Create: `plugins/dforge/reference/api-prices.json`
- Create: `plugins/dforge/tests/api-spend.test.sh`
- Modify: `plugins/dforge/tests/dforge-config.test.sh` (the `ROWS` table)
- Modify: `scripts/test-shards.mjs` (`'api-spend.test.sh': 20` in `windowsSeconds`, in alphabetical place)

**Interfaces:**
- Consumes: nothing.
- Produces: C1, C2, C3, C4, C5, C6.

**Items:** 4, 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/api-spend.test.sh`:

```bash
#!/usr/bin/env bash
# api-spend and lib/api-budget.sh: which API budgets are open, and what dforge spent on them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE DFORGE_API_PRICES DFORGE_FLOCK DR_LOCK_TENTHS
unset DFORGE_OPENAI_API_KEY DFORGE_ANTHROPIC_API_KEY DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home"; mkdir -p "$HOME/.dforge"
SPEND="$P/scripts/api-spend"
FILE="$HOME/.dforge/api-spend.json"
caps() { printf '{"apiBudgetAnthropic":%s,"apiBudgetOpenai":%s,"apiBudgetAgentRouter":%s}\n' "$1" "$2" "$3" > "$HOME/.dforge/config.json"; }
keys() { export DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL DFORGE_AGENTROUTER_API_KEY=sk-test-agentrouter-SENTINEL; }
nokeys() { unset DFORGE_ANTHROPIC_API_KEY DFORGE_OPENAI_API_KEY DFORGE_AGENTROUTER_API_KEY; }
status() { bash "$SPEND" status 2>>"$TMP/err" | tr -d '\r'; }
line() { status | grep "^api-budget $1 "; }
j() { jq -r "$1" | tr -d '\r'; }

# --- closed by default ---
check "no cap, no key: every budget is off, in the order tried" "$(status)" \
"api-budget anthropic open=false spent=0.0000 cap=0.0000 reason=off
api-budget openai open=false spent=0.0000 cap=0.0000 reason=off
api-budget agentrouter open=false spent=0.0000 cap=0.0000 reason=off"
keys
check "a key with no cap is still off" "$(line openai)" "api-budget openai open=false spent=0.0000 cap=0.0000 reason=off"

# --- A10: only the DFORGE_ variables count ---
nokeys; caps 10 10 10
export OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic
check "A10: the vendors' own variables open no budget" "$(status | grep -c 'open=false .* reason=no-key$')" "3"
unset OPENAI_API_KEY ANTHROPIC_API_KEY
export DFORGE_OPENAI_API_KEY=""
check "an empty key variable is no key" "$(line openai)" "api-budget openai open=false spent=0.0000 cap=10.0000 reason=no-key"

# --- open, add, spent ---
keys
check "a cap and a key: open" "$(line anthropic)" "api-budget anthropic open=true spent=0.0000 cap=10.0000 reason=ok"
bash "$SPEND" add openai 1.25; check "add: exit 0" "$?" "0"
check "add prints nothing" "$(bash "$SPEND" add openai 0.0005 2>&1)" ""
check "add: the amount accumulates, to four decimals" "$(line openai)" "api-budget openai open=true spent=1.2505 cap=10.0000 reason=ok"
check "add: calls are counted" "$(j '.openai.calls' < "$FILE")" "2"
check "add: the other budgets are untouched" "$(line agentrouter)" "api-budget agentrouter open=true spent=0.0000 cap=10.0000 reason=ok"
bash "$SPEND" add anthropic 9.4
check "below 95% of the cap: open" "$(line anthropic)" "api-budget anthropic open=true spent=9.4000 cap=10.0000 reason=ok"
bash "$SPEND" add anthropic 0.2
check "at or above 95% of the cap: spent" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=10.0000 reason=spent"
nokeys
check "no key is reported before spent" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=10.0000 reason=no-key"
caps 0 10 10
check "off is reported before no key" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=0.0000 reason=off"

# --- the spend file ---
keys; caps 10 10 10
export DFORGE_API_SPEND_FILE="$TMP/elsewhere.json"
bash "$SPEND" add agentrouter 2
check "DFORGE_API_SPEND_FILE moves the file" "$(j '.agentrouter.spent_usd == 2' < "$TMP/elsewhere.json")" "true"
check "the default file is untouched" "$(j '.agentrouter.spent_usd // 0' < "$FILE")" "0"
unset DFORGE_API_SPEND_FILE
rm -f "$FILE"
for _ in 1 2 3 4 5 6 7 8 9 10; do bash "$SPEND" add openai 0.1 & done; wait
check "ten adds at once all land" "$(j '.openai.calls' < "$FILE") $(line openai | sed 's/.* spent=\([0-9.]*\) .*/\1/')" "10 1.0000"

# --- the lock: one left by a killed process, and one that is held ---
LOCKBASE=$( . "$P/scripts/lib/lock.sh"; dr_lock_base "$FILE" )
: > "$LOCKBASE.lock"
bash "$SPEND" add openai 0.1; rc=$?
check "a lock file left behind does not block an add" "$rc $(j '.openai.calls' < "$FILE")" "0 11"
sleep 0 & dead=$!; wait "$dead"
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$dead" > "$LOCKBASE.lockd/pid"
DFORGE_FLOCK=no-such-flock bash "$SPEND" add openai 0.1 2>>"$TMP/err"; rc=$?
check "no flock: a lock whose owner is dead is reclaimed" "$rc $(j '.openai.calls' < "$FILE")" "0 12"
for _ in 1 2 3 4 5; do DFORGE_FLOCK=no-such-flock bash "$SPEND" add openai 0.1 & done; wait
check "no flock: five adds at once all land" "$(j '.openai.calls' < "$FILE")" "17"
check "no flock: the lock directory is gone" "$([ -e "$LOCKBASE.lockd" ] && echo left || echo gone)" "gone"
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$$" > "$LOCKBASE.lockd/pid"
DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3 bash "$SPEND" add openai 0.1 2>"$TMP/busy.err"; rc=$?
check "a lock a live process holds: the add exits 1 and adds nothing" "$rc $(j '.openai.calls' < "$FILE")" "1 17"
has "a lock a live process holds: stderr says so" "$(cat "$TMP/busy.err")" "is locked by another process"
(. "$P/scripts/lib/api-budget.sh"; DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3 api_budget_charge openai 0.1 2>/dev/null)
check "charge returns the add's status" "$?" "1"
rm -rf "$LOCKBASE.lockd"

# --- usage ---
bash "$SPEND" add nope 1 2>/dev/null; check "an unknown budget: exit 2" "$?" "2"
bash "$SPEND" add openai abc 2>/dev/null; check "an amount that is not a number: exit 2" "$?" "2"
bash "$SPEND" add openai -1 2>/dev/null; check "a negative amount: exit 2" "$?" "2"
bash "$SPEND" add openai 2>/dev/null; check "a missing amount: exit 2" "$?" "2"
bash "$SPEND" frob 2>/dev/null; check "an unknown command: exit 2" "$?" "2"
check "a refused add changes nothing" "$(j '.openai.calls' < "$FILE")" "17"

# --- the library ---
lib() { (. "$P/scripts/lib/api-budget.sh"; "$@"); }
check "key variable: anthropic" "$(lib api_budget_key_var anthropic)" "DFORGE_ANTHROPIC_API_KEY"
check "key variable: openai" "$(lib api_budget_key_var openai)" "DFORGE_OPENAI_API_KEY"
check "key variable: agentrouter" "$(lib api_budget_key_var agentrouter)" "DFORGE_AGENTROUTER_API_KEY"
lib api_budget_key_var nope >/dev/null 2>&1; check "key variable: an unknown budget fails" "$?" "1"
check "state prints the budget's status line" "$(lib api_budget_state agentrouter | tr -d '\r')" "$(line agentrouter)"
lib api_budget_state agentrouter >/dev/null; check "state: 0 when open" "$?" "0"
caps 10 10 0
lib api_budget_state agentrouter >/dev/null; check "state: 1 when closed" "$?" "1"
caps 10 10 10
lib api_budget_charge agentrouter 0.5
check "charge adds to the budget" "$(line agentrouter)" "api-budget agentrouter open=true spent=0.5000 cap=10.0000 reason=ok"

# --- the price table ---
printf '%s\n' '{"checked":"2026-11-14","models":{"m1":{"source":"https://example.invalid/pricing","input":2.5,"cached_input":0.25,"output":10}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json"
check "price: input" "$(lib api_budget_price m1 input)" "2.5"
check "price: cached input" "$(lib api_budget_price m1 cached_input)" "0.25"
check "price: output" "$(lib api_budget_price m1 output)" "10"
lib api_budget_price m2 input >/dev/null 2>&1; check "price: an unknown model fails" "$?" "1"
lib api_budget_price m1 batch >/dev/null 2>&1; check "price: an unknown field fails" "$?" "1"
unset DFORGE_API_PRICES
check "the shipped table prices the Decisions model" "$(lib api_budget_price gpt-6-luna input)" "0.1"
check "every shipped row names its source and an input price" \
  "$(j '[.models[] | select((.source | startswith("https://") | not) or (.input | type != "number"))] | length' < "$P/reference/api-prices.json")" "0"
check "the shipped table is dated" "$(j '.checked | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' < "$P/reference/api-prices.json")" "true"

# --- A8: no key value is printed or stored ---
lacks "A8: no key value in the output or the spend file" "$(status) $(cat "$TMP/err" 2>/dev/null) $(cat "$FILE")" "SENTINEL"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

In `plugins/dforge/tests/dforge-config.test.sh`, add these rows to the table between `<<'ROWS'` and `ROWS`, after the `agyReview` row (each row is key, default, a value it accepts, a value it refuses):

```
decisionApi off shadow maybe
decisionConfidence 85 90 100
apiBudgetAnthropic 0 25 1001
apiBudgetOpenai 0 25 1001
apiBudgetAgentRouter 0 25 1001
keepWarm 50 4 60
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/api-spend.test.sh; timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: `api-spend.test.sh` fails nearly every check (`scripts/api-spend` does not exist; the A8 `lacks` check and the checks that expect a failure status pass against nothing); `dforge-config.test.sh` fails the six new keys' rows.

- [ ] **Step 3: Implement**

1. `plugins/dforge/config/schema.mjs`: add the six settings of C2. These are configuration values, so they are given whole. Directly after the `agyReview` entry:

   ```js
     decisionApi: {
       type: 'enum', values: ['off', 'shadow', 'on'], default: 'off', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
       label: 'Decisions API', title: 'Auto run: OpenAI Decisions API',
       description: 'In an auto run, a planning choice with listed options goes first to OpenAI\'s Decisions API. off, the default, never calls it. shadow calls it and logs the answer but never rules. on lets a confident answer stand. Needs DFORGE_OPENAI_API_KEY and an OpenAI cap above 0.',
     },
     decisionConfidence: {
       type: 'number', default: 85, min: 50, max: 99, step: 1, unit: '%', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
       label: 'Decision floor', title: 'Decisions API: confidence floor',
       description: 'A Decisions API answer rules only when its confidence is at or above this in both option orders.',
     },
     apiBudgetAnthropic: {
       type: 'number', default: 0, min: 0, max: 1000, step: 5, zero: 'off', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
       label: 'Anthropic cap', title: 'API budget: Anthropic key (USD)',
       description: 'What auto runs may spend on rulings through DFORGE_ANTHROPIC_API_KEY, in US dollars. 0, the default, never uses the key. The count covers only what dforge spent: the vendor console is the authority.',
     },
     apiBudgetOpenai: {
       type: 'number', default: 0, min: 0, max: 1000, step: 5, zero: 'off', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
       label: 'OpenAI cap', title: 'API budget: OpenAI key (USD)',
       description: 'What auto runs may spend on rulings and Decisions API requests through DFORGE_OPENAI_API_KEY, in US dollars. 0, the default, never uses the key. The count covers only what dforge spent: the vendor console is the authority.',
     },
     apiBudgetAgentRouter: {
       type: 'number', default: 0, min: 0, max: 1000, step: 5, zero: 'off', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
       label: 'AgentRouter cap', title: 'API budget: AgentRouter (USD)',
       description: 'What auto runs may spend on rulings through DFORGE_AGENTROUTER_API_KEY, in US dollars. 0, the default, never uses the key. A cap above 0 sends ruling prompts, and any file its judge reads, to AgentRouter, a third party.',
     },
   ```

   Directly after the `autoCompactEnabled` entry (the last of group Context):

   ```js
     keepWarm: {
       type: 'number', default: 50, min: 0, max: 59, step: 1, unit: 'min', zero: 'off', group: 'Context', target: 'dforge',
       label: 'Keep warm', title: 'Keep the prompt cache warm (minutes)',
       description: 'Outside an auto run, while the session waits on background work, the cockpit submits a one-line turn after this many minutes so the prompt cache does not expire. 0 turns it off. Set 4 on the five-minute cache.',
     },
   ```

   `agyReview` must stay the key directly after `codexReview`: two suites pin that.
2. `plugins/dforge/scripts/lib/api-budget.sh`, sourced, the four functions of C5. It sources `dforge-env.sh` from its own directory for `dforge_setting`.
   - `api_budget_key_var <id>`: prints the C1 variable name; returns 1 and prints nothing for any other id.
   - `api_budget_state <id>`: reads the cap with `dforge_setting <C1 cap setting> 0`, the key through the variable name (indirect expansion; the value is only tested for emptiness and never printed), and `spent_usd` from the spend file (`${DFORGE_API_SPEND_FILE:-$HOME/.dforge/api-spend.json}`; a missing file or id is 0). It prints the C4 line with both amounts at four decimals, and returns 0 when open, 1 when closed. The reason is the first that holds, in this order: `off` (cap is 0), `no-key` (variable unset or empty), `spent` (`spent_usd >= 0.95 * cap`), else `ok`.
   - `api_budget_price <model> <field>`: reads `${DFORGE_API_PRICES:-<plugin>/reference/api-prices.json}` and prints `.models[<model>][<field>]` when it is a number; returns 1 otherwise. `<field>` is `input`, `cached_input` or `output`.
   - `api_budget_charge <id> <usd>`: runs `scripts/api-spend add <id> <usd>` and returns its status.
   - Feed `jq` its file on stdin, never as a path argument (Global Constraints, Windows).
3. `plugins/dforge/scripts/api-spend`, `set -uo pipefail`, sourcing the library.
   - `status`: `api_budget_state` for `anthropic`, `openai`, `agentrouter`, in that order; exit 0 whatever is open.
   - `add <id> <usd>`: exit 2 with a one-line message on stderr unless `<id>` is a C1 id and `<usd>` matches `^[0-9]+(\.[0-9]+)?$`. Under a lock, read the file (an absent file is `{}`), add `<usd>` to `.[id].spent_usd`, add 1 to `.[id].calls`, write to a temporary file in the same directory and `mv` it into place. Create the file's directory when it is missing. Print nothing.
   - The lock is the repository's own: source `scripts/lib/lock.sh` and run the read-modify-write as a function under `dr_locked "$(dr_lock_base "$file")" <function>`. `dr_locked` uses `flock` where it exists and otherwise a lock directory that records its owner and is reclaimed when the owner has died; it holds on uutils, and `scripts/register` and `scripts/auto-run` use it the same way. Build no lock of your own. When `dr_locked` returns nonzero the lock was not had within its wait (`DR_LOCK_TENTHS`, 10 s by default): `add` exits 1, `dr_locked`'s message stays on stderr, and the file is unchanged.
   - Any other command, or a wrong argument count: usage on stderr, exit 2.
   - Mark the file executable (`chmod +x`), as the other files in `scripts/` are.
4. `plugins/dforge/reference/api-prices.json`, shape C6. Open OpenAI's pricing page (https://developers.openai.com/api/docs/pricing; if it has moved, the pricing page the API docs link to) and record, for `gpt-6-luna` and `gpt-6-astra`, the per-million-token prices it states and the page's URL as `source`; `checked` is the date of the read. `gpt-6-luna` is `"input": 0.1` with no other field: the Decisions guide states it and says output is not charged. A price the page does not state is left out, and a model with no stated input price gets no row: its budget then closes with `no-price` in Task 5. No row for `claude-opus-5-5`: the Anthropic run is charged from the cost its CLI reports.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/api-spend.test.sh; timeout 600 bash plugins/dforge/tests/dforge-config.test.sh; timeout 60 node scripts/validate-repository.mjs; timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: both suites end `0 failed`; the validator passes (it checks every label is at most 16 characters); the cockpit tests pass (one of them requires a settings row for every schema key, and the rows are drawn from the schema).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/scripts/lib/api-budget.sh plugins/dforge/scripts/api-spend plugins/dforge/reference/api-prices.json plugins/dforge/tests/api-spend.test.sh plugins/dforge/tests/dforge-config.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): add API budgets and the spend file"
```

### Task 3: `decide ask`: the Decisions API rung

**Files:**
- Create: `plugins/dforge/scripts/decide`
- Create: `plugins/dforge/scripts/lib/decisions.mjs`
- Create: `plugins/dforge/tests/fixtures/stub-decisions/server.mjs`
- Create: `plugins/dforge/tests/decide.test.sh`
- Modify: `scripts/test-shards.mjs` (`'decide.test.sh': 40`)

**Interfaces:**
- Consumes: C1, C2 (`decisionApi`, `decisionConfidence`), C5 (`api_budget_state`, `api_budget_price`, `api_budget_charge`), C6.
- Produces: C7 (`ask`), C8 (ask lines).

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/fixtures/stub-decisions/server.mjs`:

```js
#!/usr/bin/env node
// Stand-in for POST /v1/decisions. argv: <port file> <reply file> <request log>.
// The reply file is read on every request: {"status": 200, "delayMs": 0, "body": {…}}.
// Each request is logged as one JSON line; the key is compared, never written.
import { createServer } from 'node:http'
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs'

const [portFile, replyFile, logFile] = process.argv.slice(2)
const server = createServer((req, res) => {
  let text = ''
  req.on('data', chunk => {
    text += chunk
  })
  req.on('end', () => {
    const reply = JSON.parse(readFileSync(replyFile, 'utf8'))
    const authorized = req.headers.authorization === `Bearer ${process.env.STUB_DECISIONS_KEY}`
    appendFileSync(logFile, `${JSON.stringify({ method: req.method, url: req.url, authorized, body: JSON.parse(text) })}\n`)
    setTimeout(() => {
      res.writeHead(reply.status ?? 200, { 'content-type': 'application/json' })
      res.end(JSON.stringify(reply.body ?? {}))
    }, reply.delayMs ?? 0)
  })
})
server.listen(0, '127.0.0.1', () => writeFileSync(portFile, String(server.address().port)))
```

Create `plugins/dforge/tests/decide.test.sh`:

```bash
#!/usr/bin/env bash
# decide: the Decisions API rung of an auto run's ruling ladder, against a local stub endpoint.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE AR_SESSION CLAUDE_PROJECT_DIR DFORGE_DECISIONS_TIMEOUT
unset DFORGE_ANTHROPIC_API_KEY DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_GLOBAL XDG_CONFIG_HOME

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); stub=""
trap '[ -n "$stub" ] && kill "$stub" 2>/dev/null; rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" CLAUDE_CODE_SESSION_ID=s1
export DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL STUB_DECISIONS_KEY=sk-test-openai-SENTINEL
WORK="$TMP/work"; LOG="$WORK/.dforge/decisions.jsonl"; REQ="$TMP/requests.jsonl"
mkdir -p "$HOME/.dforge" "$HOME/.claude/dforge/sessions/cockpit" "$WORK/docs" "$WORK/.dforge"
DECIDE="$P/scripts/decide"; SPEND="$P/scripts/api-spend"

settings() { printf '%s\n' "$1" > "$HOME/.dforge/config.json"; }
j() { jq -r "$1" | tr -d '\r'; }
printf '%s\n' '{"checked":"2026-11-14","models":{"gpt-6-luna":{"source":"https://example.invalid/pricing","input":0.1}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json"

git -C "$WORK" init -q
printf '.dforge/\nsecret.env\n' > "$WORK/.gitignore"
printf '# Spec\nThe lock must hold on uutils.\n' > "$WORK/docs/s.md"
printf 'TOKEN=abc\n' > "$WORK/secret.env"
printf 'state note\n' > "$WORK/.dforge/note.md"
git -C "$WORK" add -A
git -C "$WORK" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
(cd "$WORK" && bash "$P/scripts/auto-run" --session s1 start --spec docs/s.md >/dev/null 2>&1)
check "fixture: an auto run is bound to the session" "$( (cd "$WORK" && bash "$P/scripts/auto-run" status >/dev/null 2>&1); echo $?)" "0"

reply() { # reply <choice> <confidence> <reversed choice> <reversed confidence> <needs_more> <guarded>
  jq -n --arg a "$1" --argjson ca "$2" --arg b "$3" --argjson cb "$4" --argjson nm "$5" --argjson g "$6" '{status: 200, body: {answers: [
    {type: "choice", name: "ruling", choice: $a, probabilities: [], confidence: $ca},
    {type: "choice", name: "ruling_reversed", choice: $b, probabilities: [], confidence: $cb},
    {type: "predicate", name: "needs_more", probability: $nm},
    {type: "predicate", name: "guarded", probability: $g}], usage: {input_tokens: 2000000}}}' > "$TMP/reply.json"
}
raw() { printf '%s\n' "$1" > "$TMP/reply.json"; }
reply option_1 0.93 option_1 0.91 0.05 0.02
node "$P/tests/fixtures/stub-decisions/server.mjs" "$TMP/port" "$TMP/reply.json" "$REQ" & stub=$!
for _ in $(seq 1 100); do [ -s "$TMP/port" ] && break; sleep 0.1; done
export DFORGE_DECISIONS_URL="http://127.0.0.1:$(cat "$TMP/port")/v1/decisions"

ask() { out=$(cd "$WORK" && bash "$DECIDE" ask "$@" 2>>"$TMP/err"); rc=$?; out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"; }
sent() { if [ -f "$REQ" ]; then wc -l < "$REQ" | tr -d ' '; else echo 0; fi; }
logged() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
last() { tail -1 "$LOG" | j "$1"; }
spent() { bash "$SPEND" status | tr -d '\r' | sed -n 's/^api-budget openai .* spent=\([0-9.]*\) .*/\1/p'; }
Q=(--id q1 --question "Which lock does the spend file take?" --options "a noclobber lock file | flock")

# --- A1: both orders agree, confidently ---
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
ask "${Q[@]}" --evidence docs/s.md
check "A1: a confident answer in both orders rules, at the lower confidence" "$rc:$out" "0:ruling: a noclobber lock file — Decisions API (confidence 0.91)"
check "A1: one request was sent" "$(sent)" "1"
r=$(tail -1 "$REQ")
check "the request: endpoint, model and the four questions in order" \
  "$(printf '%s' "$r" | j '[.method, .url, .body.model, (.body.questions | map(.name) | join(","))] | join(" ")')" \
  "POST /v1/decisions gpt-6-luna ruling,ruling_reversed,needs_more,guarded"
check "the request: question types" "$(printf '%s' "$r" | j '.body.questions | map(.type) | join(",")')" "choice,choice,predicate,predicate"
check "the request: options in the order given, other last" "$(printf '%s' "$r" | j '.body.questions[0].choices | map(.value) | join(",")')" "option_1,option_2,other"
check "the request: options reversed, other still last" "$(printf '%s' "$r" | j '.body.questions[1].choices | map(.value) | join(",")')" "option_2,option_1,other"
check "the request: a value keeps its option's text in both orders" \
  "$(printf '%s' "$r" | j '[.body.questions[0].choices[1].description, .body.questions[1].choices[0].description] | join(" = ")')" "flock = flock"
check "the request: carries the key as a bearer token" "$(printf '%s' "$r" | j '.authorized')" "true"
has "the request: the input holds the question" "$(printf '%s' "$r" | j '.body.input')" "Which lock does the spend file take?"
has "the request: the input holds the evidence" "$(printf '%s' "$r" | j '.body.input')" "The lock must hold on uutils."
check "A16: the request is charged to openai from its input tokens" "$(spent)" "0.2000"
check "A6: the ask is logged with both answers" \
  "$(last '[.kind, .id, (.options | join("/")), .mode, .outcome, .choice, .choice_reversed, .confidence, .confidence_reversed, .needs_more, .guarded] | map(tostring) | join(" | ")')" \
  "ask | q1 | a noclobber lock file/flock | on | ruled | a noclobber lock file | a noclobber lock file | 0.93 | 0.91 | 0.05 | 0.02"

# --- A2: every way an answer fails to rule ---
while IFS='|' read -r name a ca b cb nm g token; do
  reply "$a" "$ca" "$b" "$cb" "$nm" "$g"
  ask "${Q[@]}"
  check "A2: $name" "$rc:$out" "3:no ruling reason=$token"
done <<'ROWS'
the orders disagree|option_1|0.95|option_2|0.95|0.05|0.02|disagree
the first order answers other|other|0.95|option_1|0.95|0.05|0.02|needs-more
the reversed order answers other|option_1|0.95|other|0.95|0.05|0.02|needs-more
the first confidence is below the setting|option_1|0.84|option_1|0.95|0.05|0.02|low-confidence
the reversed confidence is below the setting|option_1|0.95|option_1|0.84|0.05|0.02|low-confidence
more information is needed|option_1|0.95|option_1|0.95|0.16|0.02|needs-more
an option is guarded|option_1|0.95|option_1|0.95|0.05|0.11|guarded
ROWS
while IFS='|' read -r name ca cb nm g; do
  reply option_2 "$ca" option_2 "$cb" "$nm" "$g"
  ask "${Q[@]}"
  check "the limits are inclusive: $name" "$rc:$out" "0:ruling: flock — Decisions API (confidence 0.85)"
done <<'ROWS'
a confidence at the setting|0.85|0.99|0.05|0.02
needs_more at 0.15|0.99|0.85|0.15|0.02
guarded at 0.10|0.85|0.85|0.05|0.10
ROWS
settings '{"decisionApi":"on","apiBudgetOpenai":10,"decisionConfidence":95}'
reply option_1 0.93 option_1 0.94 0.05 0.02
ask "${Q[@]}"; check "A2: decisionConfidence moves the floor" "$rc:$out" "3:no ruling reason=low-confidence"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
raw '{"status":200,"body":{"answers":[{"type":"refusal","name":"ruling"},{"type":"choice","name":"ruling_reversed","choice":"option_1","probabilities":[],"confidence":0.95},{"type":"predicate","name":"needs_more","probability":0.05},{"type":"predicate","name":"guarded","probability":0.02}],"usage":{"input_tokens":1000}}}'
ask "${Q[@]}"; check "A2: a refusal" "$rc:$out" "3:no ruling reason=refusal"
raw '{"status":500,"body":{"error":{"message":"boom"}}}'
ask "${Q[@]}"; check "A2: a failed request" "$rc:$out" "3:no ruling reason=error"
raw '{"status":200,"body":{"answers":[{"type":"choice","name":"ruling","choice":"option_1","probabilities":[],"confidence":0.95}]}}'
ask "${Q[@]}"; check "A2: an answer with a question missing" "$rc:$out" "3:no ruling reason=error"
raw '{"status":200,"delayMs":8000,"body":{}}'
before=$(date +%s)
DFORGE_DECISIONS_TIMEOUT=1 ask "${Q[@]}"
check "A2: no answer inside the timeout" "$rc:$out" "3:no ruling reason=error"
check "the timeout bounds the wait" "$([ $(( $(date +%s) - before )) -lt 8 ] && echo yes || echo no)" "yes"
DFORGE_DECISIONS_URL="http://127.0.0.1:1/v1/decisions" ask "${Q[@]}"
check "A2: an endpoint that cannot be reached" "$rc:$out" "3:no ruling reason=error"
check "A2: only the four ruling cases above printed a ruling" "$(grep -c '^ruling:' "$TMP/all.out")" "4"

# --- A3: when no request is made ---
reply option_1 0.95 option_1 0.95 0.05 0.02
n=$(sent); l=$(logged)
settings '{"decisionApi":"off","apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: off sends and logs nothing" "$rc:$out:$(( $(sent) - n )):$(( $(logged) - l ))" "3:no ruling reason=off:0:0"
settings '{"apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: off is the default" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=off:0"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
CLAUDE_CODE_SESSION_ID=other ask "${Q[@]}"; check "A3: no run bound to the session" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=no-run:0"
settings '{"decisionApi":"on","apiBudgetOpenai":0}'
ask "${Q[@]}"; check "A3: the openai budget is closed" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=closed:0"
check "A6: an ask refused before any request is logged, with no answers" "$(last '[.outcome, .choice, .confidence, .needs_more] | map(tostring) | join(" ")')" "closed null null null"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
printf '%s\n' '{"checked":"2026-11-14","models":{}}' > "$TMP/noprices.json"
DFORGE_API_PRICES="$TMP/noprices.json" ask "${Q[@]}"; check "no price for the model closes the rung" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=closed:0"
settings '{"decisionApi":"shadow","apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: shadow sends the request and never rules" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=shadow:1"
check "A6: shadow logs what the answer would have ruled" "$(last '[.mode, .outcome, .choice] | join(" ")')" "shadow ruled a noclobber lock file"

# --- A4, A5: what may be sent as evidence ---
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
printf 'outside\n' > "$TMP/outside.txt"
head -c 400001 /dev/zero | tr '\0' 'a' > "$WORK/big.txt"
n=$(sent)
while IFS='|' read -r name file; do
  ask "${Q[@]}" --evidence "$file"
  check "A4: $name" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=evidence:0"
done <<ROWS
a file outside the working tree and both roots|$TMP/outside.txt
a file git ignores|secret.env
more than 400000 bytes|big.txt
a file that does not exist|docs/missing.md
ROWS
check "A6: a refused evidence file is logged" "$(last '.outcome')" "evidence"
ask "${Q[@]}" --evidence docs/s.md --evidence .dforge/note.md
check "A5: a file under the state root is accepted though git ignores it" "$rc:$(( $(sent) - n ))" "0:1"
has "A5: its text is sent" "$(tail -1 "$REQ" | j '.body.input')" "state note"
# The documents root in the darkmem mirror, outside the working tree (the fixture
# tests/dforge-dir.test.sh uses: home, repository, project, documents store, progress store).
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$WORK" proj darkmem local)
jq '. + {decisionApi: "on", apiBudgetOpenai: 10}' < "$HOME/.dforge/config.json" > "$TMP/config.json" && mv "$TMP/config.json" "$HOME/.dforge/config.json"
docs=$(cd "$WORK" && bash "$P/scripts/dforge-path" docs | tr -d '\r')
mkdir -p "$docs/specs"; printf 'mirror spec text\n' > "$docs/specs/s.md"
check "fixture: the documents root is outside the working tree" "$(case "$docs" in "$WORK"/*) echo inside ;; *) echo outside ;; esac)" "outside"
ask "${Q[@]}" --evidence "$docs/specs/s.md"
check "A5: a spec under the documents root outside the working tree is accepted" "$rc:$(( $(sent) - n ))" "0:2"
has "A5: the mirror spec's text is sent" "$(tail -1 "$REQ" | j '.body.input')" "mirror spec text"

# --- usage ---
(cd "$WORK" && bash "$DECIDE" ask --question q --options "a | b" 2>/dev/null); check "a missing --id: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" ask --id q2 --question q --options "only one" 2>/dev/null); check "fewer than two options: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" ask --id q2 --question q --options "a | other" 2>/dev/null); check "an option named other: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" frob 2>/dev/null); check "an unknown command: exit 2" "$?" "2"

# --- A8: no key value is printed, logged or stored ---
lacks "A8: no key value in stdout, stderr, the log or the spend file" \
  "$(cat "$TMP/all.out" "$TMP/err" "$LOG" "$HOME/.dforge/api-spend.json" 2>/dev/null)" "SENTINEL"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/decide.test.sh`
Expected: nearly every check fails (`scripts/decide` does not exist). The fixture checks, `the timeout bounds the wait` and the `lacks` checks pass against nothing; that is the correct red run.

- [ ] **Step 3: Implement**

1. `plugins/dforge/scripts/decide` (bash, `set -uo pipefail`, executable) parses the command. This task builds `ask`; `record` and `report` exit 2 with `decide: <command> is not built yet` until Task 4. Usage errors (exit 2, one line on stderr): no `--id`, no `--question`, fewer than two options after splitting `--options` on `|` and trimming blanks, an empty option, an option equal to `other`, an unknown flag or command.
2. `ask` runs these gates in this order, and the first that fails ends it with `no ruling reason=<token>` on stdout and exit 3:
   1. Mode: `dforge_setting decisionApi off`. `off` prints `reason=off` and writes no log line. Every later outcome, ruled or not, appends one C8 ask line.
   2. Bound run: `AR_SESSION=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}` and `ar_bound` from `scripts/lib/auto-run.sh`; not bound is `no-run`.
   3. Budget: `api_budget_state openai` must return 0 and `api_budget_price gpt-6-luna input` must print a price; otherwise `closed`.
   4. Evidence: each `--evidence` file must be a regular file whose canonical path lies under the documents root (`scripts/dforge-path docs`, run in the working directory) or the state root (`scripts/dforge-path state`), or else inside the working tree (`git rev-parse --show-toplevel`) and not ignored (`git check-ignore -q` exits 1). The files' sizes must total at most 400000 bytes. Anything else is `evidence`. Compare canonical paths (`cd <dir> && pwd -P`), normalised with `cygpath -m` where `cygpath` exists.
   5. The request, made by `node scripts/lib/decisions.mjs`, which prints one JSON object the wrapper reads: the outcome token and the six answer fields of C8, plus `input_tokens`.
3. `plugins/dforge/scripts/lib/decisions.mjs` reads the question, the options, the evidence file paths, the confidence floor (`decisionConfidence` as a fraction: `setting / 100`) and the timeout from its arguments, and the key from `DFORGE_OPENAI_API_KEY` in its environment (never from an argument). It sends one `POST` to `DFORGE_DECISIONS_URL` (default `https://api.openai.com/v1/decisions`) with `Authorization: Bearer <key>` and `Content-Type: application/json`, aborted after `DFORGE_DECISIONS_TIMEOUT` seconds (default 30):
   - `model`: `gpt-6-luna`.
   - `input`: the question, the options as a numbered list, then each evidence file as a line `--- <path as given> ---` followed by its text.
   - `questions`, in this order, each with `type`, `name` and `instructions`: `ruling` (`choice`; `choices` are `{value: "option_<i>", description: <the i-th option's text>}` in the order given, then `{value: "other", description: "None of the listed options fits."}`); `ruling_reversed` (the same listed choices in reverse order, the same `value` for the same text, `other` still last); `needs_more` (`predicate`: "Choosing correctly needs information that is not in the input, such as reading source files or running code."); `guarded` (`predicate`: "One of the options involves an irreversible or destructive operation, a security-sensitive action, or a change outside the working directory.").
   - The outcome is the first of these that holds: `error` (the request threw, timed out, answered a status other than 200, or the body has no answer named for one of the four questions, or a choice answer names a value that was not sent); `refusal` (any answer's `type` is `refusal`); `needs-more` (either choice is `other`); `disagree` (the two choices differ); `low-confidence` (either `confidence` is below the floor); `needs-more` (`needs_more.probability > 0.15`); `guarded` (`guarded.probability > 0.10`); else `ruled`.
   - `choice` and `choice_reversed` in the output are the option's text (or `other`), not the `option_<i>` value. All six answer fields are `null` on `error`; on `refusal` each field is what its answer gave, `null` for a refused one.
4. The wrapper then charges and logs: when `input_tokens` is a number, `api_budget_charge openai <input_tokens * price / 1000000>` (four decimals), and a charge that fails prints `decide: the charge to openai was not recorded` on stderr and changes nothing else (C5); it appends the C8 ask line to `<state>/decisions.jsonl` (state root from `scripts/dforge-path state`); and it prints:
   - mode `shadow`: `no ruling reason=shadow`, exit 3, whatever the outcome (the log line keeps the real outcome, `ruled` included);
   - mode `on` and outcome `ruled`: `ruling: <choice text> — Decisions API (confidence <c>)`, `<c>` the lower confidence with two decimals, exit 0;
   - otherwise `no ruling reason=<outcome>`, exit 3.
5. Nothing prints the key, and no error message echoes a request header. A failed request is not retried.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/decide.test.sh`
Expected: ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/decide plugins/dforge/scripts/lib/decisions.mjs plugins/dforge/tests/fixtures/stub-decisions/server.mjs plugins/dforge/tests/decide.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): add the Decisions API ruling rung"
```

### Task 4: `decide record` and `decide report`

**Files:**
- Modify: `plugins/dforge/scripts/decide`
- Modify: `plugins/dforge/scripts/lib/decisions.mjs` (only if the report is computed there)
- Test: `plugins/dforge/tests/decide.test.sh`

**Interfaces:**
- Consumes: C7 (`ask`), C8 (ask lines), C2 (`decisionConfidence`).
- Produces: C7 (`record`, `report`), C8 (record lines, the report's lines).

**Items:** 1
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/decide.test.sh`, insert this section directly above the `# --- A8:` section:

```bash
# --- A7: record and report ---
rec() { (cd "$WORK" && bash "$DECIDE" record "$@" 2>>"$TMP/err"); }
report() { (cd "$WORK" && bash "$DECIDE" report 2>>"$TMP/err") | tr -d '\r'; }
l=$(logged)
rec --id q1 --ruling "flock"; check "A7: record takes a listed option" "$?" "0"
check "A7: the record line" "$(tail -1 "$LOG" | tr -d '\r')" '{"kind":"record","id":"q1","ruling":"flock"}'
rec --id q1 --ruling "other"; check "A7: record takes other" "$?" "0"
rec --id q1 --ruling "a third way"; check "A7: record refuses any other text: exit 2" "$?" "2"
rec --id never-asked --ruling "flock"; check "A7: record refuses an id that was never asked: exit 2" "$?" "2"
check "A7: a refused record writes nothing" "$(( $(logged) - l ))" "2"

ask_line() { # ask_line <id> <confidence> <reversed confidence> <choice> [reversed choice]
  printf '{"kind":"ask","id":"%s","options":["A","B"],"mode":"shadow","outcome":"ruled","choice":"%s","choice_reversed":"%s","confidence":%s,"confidence_reversed":%s,"needs_more":0.05,"guarded":0.02}\n' "$1" "$4" "${5:-$4}" "$2" "$3"
}
rec_line() { printf '{"kind":"record","id":"%s","ruling":"%s"}\n' "$1" "$2"; }
fixture() { # fixture <confident asks> <how many of their records say B>
  : > "$LOG"
  for i in $(seq 1 "$1"); do
    ask_line "c$i" 0.97 0.95 A >> "$LOG"
    if [ "$i" -le "$2" ]; then rec_line "c$i" B >> "$LOG"; else rec_line "c$i" A >> "$LOG"; fi
  done
  ask_line low1 0.75 0.72 A >> "$LOG"; rec_line low1 B >> "$LOG"
  ask_line mid1 0.90 0.82 A >> "$LOG"; rec_line mid1 A >> "$LOG"
  ask_line split1 0.99 0.99 A B >> "$LOG"; rec_line split1 A >> "$LOG"
  ask_line unrecorded 0.99 0.99 A >> "$LOG"
  printf '{"kind":"ask","id":"refused","options":["A","B"],"mode":"shadow","outcome":"evidence","choice":null,"choice_reversed":null,"confidence":null,"confidence_reversed":null,"needs_more":null,"guarded":null}\n' >> "$LOG"
  rec_line refused A >> "$LOG"
}
fixture 19 1
check "A7: report counts matches per band of the lower confidence" "$(report)" \
"band 50-59: 0 recorded, 0 match
band 60-69: 0 recorded, 0 match
band 70-79: 1 recorded, 0 match
band 80-89: 1 recorded, 1 match
band 90-100: 20 recorded, 18 match
promote: no (20 recorded, 90% match)"
fixture 19 0
check "A7: 20 confident items, exactly 95% matching, promote" "$(report | tail -1)" "promote: yes"
fixture 18 0
check "A7: fewer than 20 confident recorded items never promote" "$(report | tail -1)" "promote: no (19 recorded, 94% match)"
: > "$LOG"
check "A7: an empty log" "$(report | tail -1)" "promote: no (0 recorded, 0% match)"
settings '{"decisionApi":"on","apiBudgetOpenai":10,"decisionConfidence":99}'
fixture 20 0
check "A7: decisionConfidence decides which items count toward promotion" "$(report | tail -1)" "promote: no (1 recorded, 0% match)"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
```

How the expected lines follow from the fixture: `split1` answered `A` in one order and `B` in the other, so it never matches, and its lower confidence 0.99 puts it in band 90-100 and among the confident items; `unrecorded` has no record line and `refused` has no confidences, so neither is an item. `fixture 19 1` has 20 confident recorded items (the 19 plus `split1`), 18 of them matching: 90%. `fixture 19 0` has 20 with 19 matching: exactly 95%. `fixture 18 0` has 19 with 18 matching. With the floor at 99 only `split1` counts.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/decide.test.sh`
Expected: every `A7:` check fails with exit 2 (`record` and `report` are not built yet); the earlier checks still pass.

- [ ] **Step 3: Implement**

1. `decide record --id <id> --ruling <choice>`: find the last C8 ask line with that id in `<state>/decisions.jsonl`. Exit 2 with a one-line message on stderr when there is none, or when `<choice>` is neither one of that line's `options` (exact text) nor `other`. Otherwise append `{"kind":"record","id":<id>,"ruling":<choice>}` as one compact JSON line and exit 0. It needs no bound run and no budget: the ruling it records came from a judge.
2. `decide report`: read the log (a missing file is an empty log). An item is an id whose last ask line has a number in both `confidence` fields and which has a record line; its ruling is its last record line's. Its confidence is the lower of the two as a whole percent, computed without floating-point drift: round the fraction times 10000 to the nearest integer, then divide by 100 in integers (0.29 is 29, not 28; 0.859 is 85). It matches when `choice` equals `choice_reversed` and equals the recorded ruling.
   - Print the five band lines of C8 in order, always, each counting the items whose confidence falls in the band (`90-100` includes 100; an item below 50 is in no band).
   - Then the promote line, over the items whose confidence is at or above `dforge_setting decisionConfidence 85`: `promote: yes` when there are at least 20 and at least 95% of them match (compare `matches * 100 >= items * 95`, in integers); otherwise `promote: no (<n> recorded, <p>% match)`, `<p>` the percentage rounded down and 0 when `<n>` is 0.
   - Exit 0. The report changes nothing: only the owner changes `decisionApi`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/decide.test.sh`
Expected: ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/decide plugins/dforge/scripts/lib/decisions.mjs plugins/dforge/tests/decide.test.sh
git commit -m "feat(dforge): record and report Decisions API rulings"
```

### Task 5: `run-api-judge`: roster, chain and status lines

**Files:**
- Create: `plugins/dforge/scripts/run-api-judge`
- Create: `plugins/dforge/tests/fixtures/stub-api-judge/common.sh`, `plugins/dforge/tests/fixtures/stub-api-judge/claude`, `plugins/dforge/tests/fixtures/stub-api-judge/codex`
- Create: `plugins/dforge/tests/api-judge.test.sh`
- Modify: `plugins/dforge/reference/ladder.md` (the `api-judge` block, after the `agy-judge` section)
- Modify: `plugins/dforge/tests/lanes.test.sh` (pin the block)
- Modify: `scripts/test-shards.mjs` (`'api-judge.test.sh': 120`)

**Interfaces:**
- Consumes: C1, C5 (`api_budget_state`, `api_budget_price`), C6, C11 (Task 1's note).
- Produces: C9, C10 except the `spent=` amounts, the reasons `wrote` and `key-in-reply`, and the child's environment, which Task 6 adds.

**Items:** 4, 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Read `docs/dforge/notes/2026-11-14-api-judge-cli-check.md` first. The stubs below print what the CLIs' documentation describes: one JSON object with `result` and `total_cost_usd` for `claude -p --output-format json`, and for `codex exec --json` a line stream with an `item.completed` agent message and a `turn.completed` line carrying `usage`. Where the note's `## Cost and usage fields` names a different field or event, change the stub's `reply` and `usage` functions to print the note's shape; change nothing else in the test code. Where the note's `## Results` disproves a CLI, leave its budget's rows out of the block, the lanes pin and the `ladder` fixture, and drop the checks that name that budget.

Create `plugins/dforge/tests/fixtures/stub-api-judge/common.sh`:

```bash
# Sourced by the stub judge CLIs: logs what the child was given, then acts on its mode.
# Modes: ok (default), silent, fail, slow-fail, noverdict, slow, hang, hang-usage,
# leak, write, write-ignored, commit.
VERDICT=$'## Verdict\nruling: a noclobber lock file — it holds on uutils\n'

stub_log() { # stub_log <budget> <args…>
  budget=$1; shift
  upper=$(printf '%s' "$budget" | tr '[:lower:]' '[:upper:]')
  eval "mode=\${STUB_JUDGE_$upper:-ok}"
  if [ -n "${STUB_JUDGE_ARGS_LOG:-}" ]; then
    { printf 'budget %s\n' "$budget"; for arg in "$@"; do printf '%s\n' "$arg"; done; printf '%s\n' '--'; } >> "$STUB_JUDGE_ARGS_LOG"
  fi
  if [ -n "${STUB_JUDGE_STDIN_LOG:-}" ] && [ ! -t 0 ]; then cat >> "$STUB_JUDGE_STDIN_LOG"; fi
  if [ -n "${STUB_JUDGE_ENV_LOG:-}" ]; then
    { printf 'budget %s\n' "$budget"
      env | grep -E '^(DFORGE_[A-Z_]*|OPENAI_API_KEY|ANTHROPIC_API_KEY)=' | while IFS='=' read -r name value; do
        printf '%s %s\n' "$name" "$(printf '%s' "$value" | sha256sum | cut -c1-16)"
      done
      printf 'CODEX_HOME %s\n' "${CODEX_HOME:-unset}"
      printf '%s\n' '--'; } >> "$STUB_JUDGE_ENV_LOG"
  fi
  if [ -n "${STUB_JUDGE_PID_FILE:-}" ]; then printf '%s\n' "$$" > "$STUB_JUDGE_PID_FILE"; fi
}

stub_run() {
  case "$mode" in
    ok | silent) reply "$VERDICT" ;;
    fail) printf 'stub judge: failed\n' >&2; exit 1 ;;
    slow-fail) sleep "${STUB_JUDGE_SLOW:-3}"; exit 1 ;;
    noverdict) reply "I would pick the first option." ;;
    slow) sleep "${STUB_JUDGE_SLOW:-3}"; reply "$VERDICT" ;;
    hang) exec sleep 300 ;;
    hang-usage) usage; exec sleep 300 ;;
    leak) reply "$VERDICT${STUB_JUDGE_LEAK:-}" ;;
    write) printf 'stray\n' > stray.txt; reply "$VERDICT" ;;
    write-ignored) mkdir -p .dforge; printf 'scratch\n' > .dforge/scratch.txt; reply "$VERDICT" ;;
    commit) git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m stray; reply "$VERDICT" ;;
  esac
}
```

Create `plugins/dforge/tests/fixtures/stub-api-judge/claude` (executable):

```bash
#!/usr/bin/env bash
# Stand-in for `claude --bare -p --output-format json`. STUB_JUDGE_ANTHROPIC is its mode.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
stub_log anthropic "$@"
usage() { :; }
reply() { # reply <text> — one result object, with the cost unless the mode is silent
  if [ "$mode" = silent ]; then jq -cn --arg t "$1" '{type: "result", subtype: "success", is_error: false, result: $t}'
  else jq -cn --arg t "$1" --argjson c "${STUB_JUDGE_COST:-0.25}" '{type: "result", subtype: "success", is_error: false, result: $t, total_cost_usd: $c}'; fi
}
stub_run
```

Create `plugins/dforge/tests/fixtures/stub-api-judge/codex` (executable):

```bash
#!/usr/bin/env bash
# Stand-in for `codex exec --json`. Its budget is agentrouter when an argument names
# agentrouter.org, openai otherwise; STUB_JUDGE_OPENAI or STUB_JUDGE_AGENTROUTER is its mode.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
budget=openai; last=""; prev=""
for arg in "$@"; do
  case "$arg" in *agentrouter.org*) budget=agentrouter ;; esac
  case "$prev" in -o | --output-last-message) last=$arg ;; esac
  prev=$arg
done
stub_log "$budget" "$@"
usage() {
  [ "$mode" = silent ] || printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1000000,"cached_input_tokens":200000,"output_tokens":100000}}'
}
reply() { # reply <text> — the event stream, and the last-message file when one was asked for
  printf '%s\n' '{"type":"thread.started","thread_id":"t-1"}'
  jq -cn --arg t "$1" '{type: "item.completed", item: {id: "item_1", type: "agent_message", text: $t}}'
  usage
  [ -z "$last" ] || printf '%s' "$1" > "$last"
}
stub_run
```

Create `plugins/dforge/tests/api-judge.test.sh`:

```bash
#!/usr/bin/env bash
# run-api-judge: a ruling on the first open API budget, against stub judge CLIs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE AR_SESSION CLAUDE_PROJECT_DIR CODEX_HOME
unset OPENAI_API_KEY ANTHROPIC_API_KEY API_JUDGE_BEAT API_JUDGE_CHAIN
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_GLOBAL XDG_CONFIG_HOME

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" CLAUDE_CODE_SESSION_ID=s1
export DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL DFORGE_AGENTROUTER_API_KEY=sk-test-agentrouter-SENTINEL
WORK="$TMP/work"; STATE="$WORK/.dforge"; REPORT="$STATE/rulings-preexec-1-report.md"; JLOG="$STATE/api-judge.log"
mkdir -p "$HOME/.dforge" "$HOME/.claude/dforge/sessions/cockpit" "$WORK/docs" "$STATE" "$TMP/ws" "$TMP/mirror"
RUN="$P/scripts/run-api-judge"; SPEND="$P/scripts/api-spend"
export API_JUDGE_CLAUDE="$P/tests/fixtures/stub-api-judge/claude" API_JUDGE_CODEX="$P/tests/fixtures/stub-api-judge/codex"
export STUB_JUDGE_ARGS_LOG="$TMP/args.log" STUB_JUDGE_STDIN_LOG="$TMP/stdin.log" STUB_JUDGE_ENV_LOG="$TMP/env.log" STUB_JUDGE_PID_FILE="$TMP/stub.pid"

caps() { printf '{"apiBudgetAnthropic":%s,"apiBudgetOpenai":%s,"apiBudgetAgentRouter":%s}\n' "$1" "$2" "$3" > "$HOME/.dforge/config.json"; }
fresh() { rm -f "$HOME/.dforge/api-spend.json"; }
ladder() { # ladder <seconds> — the three rows of the api-judge block, with one bound
  printf '%s\n' '# fixture' '' '```api-judge' "anthropic claude-opus-5-5 medium $1" "openai gpt-6-astra xhigh $1" "agentrouter gpt-6-astra xhigh $1" '```' > "$TMP/ladder.md"
}
printf '%s\n' '{"checked":"2026-11-14","models":{"gpt-6-astra":{"source":"https://example.invalid/pricing","input":2,"cached_input":0.5,"output":8}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json" API_JUDGE_LADDER="$TMP/ladder.md"
ladder 30

git -C "$WORK" init -q
printf '.dforge/\n' > "$WORK/.gitignore"
printf '# Spec\n' > "$WORK/docs/s.md"
git -C "$WORK" add -A
git -C "$WORK" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
(cd "$WORK" && bash "$P/scripts/auto-run" --session s1 start --spec docs/s.md >/dev/null 2>&1)
check "fixture: an auto run is bound to the session" "$( (cd "$WORK" && bash "$P/scripts/auto-run" status >/dev/null 2>&1); echo $?)" "0"
printf 'Rule on the lock.\n' > "$TMP/prompt.md"

run() { # run [env arguments…] — one ruling with the fixture prompt, the arguments given to env
  rm -f "$TMP/args.log" "$TMP/stdin.log" "$TMP/env.log" "$TMP/stub.pid"
  out=$(cd "$WORK" && env "$@" bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --add-dir "$TMP/ws" --add-dir "$TMP/mirror" 2>>"$TMP/err"); rc=$?
  out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"
}
status_lines() { printf '%s\n' "$out" | grep ' status='; }
tried() { status_lines | sed 's/^api-judge \([a-z]*\)[: ].* status=\([A-Z]*\) .* reason=\([a-z-]*\)$/\1 \2 \3/' | tr '\n' ' '; }
started() { if [ -f "$TMP/args.log" ]; then grep -c '^budget ' "$TMP/args.log"; else echo 0; fi; }
given() { cat "$TMP/args.log" "$TMP/stdin.log" 2>/dev/null; }
report() { if [ -e "$REPORT" ]; then echo present; else echo absent; fi; }

# --- A11: the first open budget that returns a verdict writes the report ---
caps 1000 1000 1000
run
check "first open budget wins: exit 0 and one status line" "$rc $(tried)" "0 anthropic OK none "
has "A11: the status line names the budget, model, effort and report" "$out" "api-judge anthropic:claude-opus-5-5/medium status=OK exit=0 out=$REPORT "
check "A11: the report is the reply" "$(head -1 "$REPORT" | tr -d '\r')" "## Verdict"
check "A11: only the first budget's CLI ran" "$(started)" "1"
check "A11: the status line is logged" "$(grep -c ' status=OK ' "$JLOG")" "1"
has "A12: a started line is printed when the row begins" "$out" "api-judge anthropic:claude-opus-5-5/medium started"
has "the judge is given the ruling prompt" "$(given)" "Rule on the lock."
has "the judge is told to reply with the report" "$(given)" "You cannot write files. Reply with the whole report as your answer."
check "A18: each --add-dir directory reaches the Anthropic CLI" \
  "$(grep -cxF -e "$TMP/ws" -e "$TMP/mirror" "$TMP/args.log") $(grep -qxF -e '--add-dir' "$TMP/args.log" && echo flag)" "2 flag"

# --- A13: a failed budget hands on, and a verdict is required ---
run STUB_JUDGE_ANTHROPIC=fail
check "A13: a failed run is FAILED and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED error openai OK none "
check "A11: one status line per budget tried, logged too" "$(tail -2 "$JLOG" | grep -c ' status=')" "2"
run STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
check "A13: a reply that does not open with the verdict heading is FAILED" "$rc $(tried)" "0 anthropic FAILED no-verdict openai FAILED no-verdict agentrouter OK none "
check "A11: the budgets are tried in the block's order" "$(grep '^budget ' "$TMP/args.log" | tr '\n' ' ')" "budget anthropic budget openai budget agentrouter "

# --- the flags that confine a judge (all three ran in the run above) ---
argsof() { awk -v b="budget $1" '$0 == b { f = 1; next } f && $0 == "--" { exit } f' "$TMP/args.log"; }
after() { # after <budget> <flag> — the argument that follows <flag> on that budget's command line
  argsof "$1" | awk -v f="$2" 'p { print; exit } $0 == f { p = 1 }'
}
check "the Anthropic judge runs bare" "$(argsof anthropic | grep -cxF -e '--bare')" "1"
check "the Anthropic judge's tools are Read, Grep and Glob only" "$(after anthropic --tools)" "Read,Grep,Glob"
check "the Anthropic judge runs on the row's model" "$(after anthropic --model)" "claude-opus-5-5"
check "the Anthropic judge runs at the row's effort" "$(after anthropic --effort)" "medium"
for b in openai agentrouter; do
  check "the $b judge's sandbox is read-only" "$(after "$b" --sandbox)$(after "$b" -s)" "read-only"
done
check "no judge is given wider permissions" "$(grep -c -e 'dangerously' -e 'danger-full-access' -e 'workspace-write' "$TMP/args.log")" "0"
printf 'stale\n' > "$REPORT"
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail STUB_JUDGE_AGENTROUTER=noverdict
check "A13: no budget produced a report: exit 3" "$rc $(tried)" "3 anthropic FAILED error openai FAILED error agentrouter FAILED no-verdict "
check "A13: no report file is left, a stale one included" "$(report)" "absent"

# --- A12, A13: progress lines and the bounds ---
fresh
run API_JUDGE_BEAT=1 STUB_JUDGE_ANTHROPIC=slow STUB_JUDGE_SLOW=3
check "A12: a running line is printed while the row runs" "$([ "$(printf '%s\n' "$out" | grep -c '^api-judge anthropic running [0-9]*s$')" -ge 1 ] && echo yes || echo no)" "yes"
check "a slow run inside its bound still rules" "$rc" "0"
ladder 2
before=$(date +%s)
run STUB_JUDGE_ANTHROPIC=hang
check "A13: a run past its seconds is TIMEOUT and ends the chain" "$rc $(tried)" "3 anthropic TIMEOUT timeout "
has "A13: the timeout line" "$out" "api-judge anthropic:claude-opus-5-5/medium status=TIMEOUT exit=124 out=- "
check "A13: no further budget is tried after a timeout" "$(started)" "1"
check "A13: the timed-out CLI is stopped" "$(kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped)" "stopped"
check "A13: the row's seconds bound the wait" "$([ $(( $(date +%s) - before )) -lt 20 ] && echo yes || echo no)" "yes"
ladder 30
before=$(date +%s)
run API_JUDGE_CHAIN=2 STUB_JUDGE_ANTHROPIC=hang
check "A13: the chain's seconds bound a row that has more of its own" "$rc $(tried)$([ $(( $(date +%s) - before )) -lt 20 ] && echo bounded)" "3 anthropic TIMEOUT timeout bounded"
before=$(date +%s)
run API_JUDGE_CHAIN=5 STUB_JUDGE_ANTHROPIC=slow-fail STUB_JUDGE_SLOW=3 STUB_JUDGE_OPENAI=hang
check "A13: a later row gets only what is left of the chain" "$rc $(tried)$([ $(( $(date +%s) - before )) -lt 20 ] && echo bounded)" "3 anthropic FAILED error openai TIMEOUT timeout bounded"

# --- A14: a closed budget starts no CLI ---
fresh; caps 0 0 0
run
check "A14: cap 0 skips every budget" "$rc $(tried)$(started)" "3 anthropic SKIPPED off openai SKIPPED off agentrouter SKIPPED off 0"
has "A14: a skipped line" "$out" "api-judge anthropic:claude-opus-5-5/medium status=SKIPPED exit=0 out=- spent=0.0000 reason=off"
caps 1000 1000 1000
run -u DFORGE_ANTHROPIC_API_KEY ANTHROPIC_API_KEY=vendor-anthropic
check "A14: no key skips the budget, whatever the vendor's variable holds" "$rc $(tried)" "0 anthropic SKIPPED no-key openai OK none "
run -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_OPENAI_API_KEY -u DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic
check "A10: with only the vendors' variables set no CLI starts" "$rc $(tried)$(started)" "3 anthropic SKIPPED no-key openai SKIPPED no-key agentrouter SKIPPED no-key 0"
fresh; caps 10 1000 1000; bash "$SPEND" add anthropic 9.6
run
check "A14: spend at 95% of the cap skips the budget" "$rc $(tried)" "0 anthropic SKIPPED spent openai OK none "
fresh; caps 1000 1000 1000
printf '%s\n' '{"checked":"2026-11-14","models":{}}' > "$TMP/noprices.json"
run DFORGE_API_PRICES="$TMP/noprices.json" STUB_JUDGE_ANTHROPIC=fail
check "A14: no price row skips openai and agentrouter, never anthropic" "$rc $(tried)" "3 anthropic FAILED error openai SKIPPED no-price agentrouter SKIPPED no-price "

# --- A17: auto runs only ---
run CLAUDE_CODE_SESSION_ID=other
check "A17: no run bound: one line, exit 3, no CLI" "$rc|$out|$(started)" "3|api-judge none status=SKIPPED exit=3 out=- spent=0.0000 reason=no-run|0"

# --- --dry-run and usage ---
rm -f "$TMP/args.log"
dry=$(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --dry-run 2>>"$TMP/err" | tr -d '\r'); printf '%s\n' "$dry" >> "$TMP/all.out"
check "--dry-run names each open budget's command and starts nothing" "$(printf '%s\n' "$dry" | grep -c '^api-judge [a-z]*:[^ ]* dry-run: ') $(started)" "3 0"
has "--dry-run shows a key as its variable's name" "$dry" '$DFORGE_ANTHROPIC_API_KEY'
has "--dry-run: the Anthropic line runs bare" "$(printf '%s\n' "$dry" | grep '^api-judge anthropic:')" "--bare"
has "--dry-run: the Anthropic line carries the tool limit" "$(printf '%s\n' "$dry" | grep '^api-judge anthropic:')" "Read,Grep,Glob"
check "--dry-run: both Codex lines carry the read-only sandbox" "$(printf '%s\n' "$dry" | grep -c 'read-only')" "2"
(cd "$WORK" && bash "$RUN" --report "$REPORT" --cwd "$WORK" 2>/dev/null); check "a missing --prompt: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/none.md" --report "$REPORT" --cwd "$WORK" 2>/dev/null); check "a prompt file that does not exist: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$TMP/nowhere" 2>/dev/null); check "a --cwd that is not a directory: exit 2" "$?" "2"
(cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --cwd "$WORK" 2>/dev/null); check "a missing --report: exit 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

In `plugins/dforge/tests/lanes.test.sh`, add after the `agy-judge` checks:

```bash
# --- api-judge -----------------------------------------------------------------
api=$(block api-judge)
check "api-judge rows, in the order tried" "$api" "anthropic claude-opus-5-5 medium 1800
openai gpt-6-astra xhigh 1800
agentrouter gpt-6-astra xhigh 1800"
check "api-judge rows are budget model effort seconds" \
  "$(printf '%s\n' "$api" | awk 'NF != 4 || $1 !~ /^(anthropic|openai|agentrouter)$/ || $4 !~ /^[0-9]+$/' | wc -l | tr -d ' ')" "0"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 600 bash plugins/dforge/tests/api-judge.test.sh; timeout 600 bash plugins/dforge/tests/lanes.test.sh`
Expected: `api-judge.test.sh` passes its fixture check and fails nearly all the rest (`scripts/run-api-judge` does not exist; `no judge is given wider permissions` and the bounded-wait comparisons can pass against nothing); `lanes.test.sh` fails the two `api-judge` checks.

- [ ] **Step 3: Implement**

1. `plugins/dforge/reference/ladder.md`: below the `agy-judge` section add a section `## API-billed ruling judges` with two sentences (an auto run tries these budgets, in this order, before the subscription's `judge-opus` seat, through `scripts/run-api-judge`; the whole chain has 2400 seconds and a row gets its own seconds or what is left) and the fenced `api-judge` block of C9.
2. `plugins/dforge/scripts/run-api-judge` (bash, `set -uo pipefail`, executable), sourcing `lib/api-budget.sh`, `lib/auto-run.sh`, `lib/timeout.sh` and `lib/native-path.sh`. Its header comment states the usage, the output lines and the exit codes of C10.
   - Arguments: `--prompt` (an existing file), `--report`, `--cwd` (an existing directory), any number of `--add-dir`, `--dry-run`. Anything missing or unknown is a one-line message on stderr and exit 2, as is a missing `jq` or `timeout`.
   - With no run bound (`AR_SESSION=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}`, `ar_bound`): print and log the `reason=no-run` line of C10, exit 3.
   - Delete a file already at `--report`. Read the rows of the `api-judge` block from `${API_JUDGE_LADDER:-<plugin>/reference/ladder.md}`.
   - Every line this script prints goes to stdout and is appended to `<state>/api-judge.log`, the state root being what `scripts/dforge-path state` prints when run in `--cwd`.
   - For each row, in order: stop with exit 3 when none of the chain's seconds (`${API_JUDGE_CHAIN:-2400}`, counted from the script's start) is left. The row's bound is its own seconds or what is left, whichever is less.
   - A closed budget prints `status=SKIPPED exit=0 out=- spent=0.0000 reason=<off|no-key|spent>` (the reason `api_budget_state` gave) and goes on to the next row. For `openai` and `agentrouter`, a model for which `api_budget_price <model> input` or `api_budget_price <model> output` fails is `SKIPPED … reason=no-price`.
   - `--dry-run`: for an open row print `api-judge <budget>:<model>/<effort> dry-run: <the command line>` with the key shown as `$<its C1 variable name>`, start nothing, and go on. Exit 0 when at least one row was open, 3 otherwise.
   - Otherwise print `api-judge <budget>:<model>/<effort> started` and start the CLI in the background with its working directory at `--cwd`, its standard input the prompt or `/dev/null` (never the script's own), and its output captured in files inside a `mktemp -d` directory that a trap removes. The child's stderr is never printed. Bound the run the way `scripts/run-agy-review.sh` bounds agy (`"$DFORGE_TIMEOUT" -k`), and stop the CLI's own children too (Global Constraints, uutils).
   - While it runs, print `api-judge <budget> running <seconds>s` each time `${API_JUDGE_BEAT:-300}` seconds have passed since the row's last line.
   - The command lines are C11's: `claude` for `anthropic` (found as `${API_JUDGE_CLAUDE:-claude}` on PATH, else `$HOME/.local/bin/claude`), with the model and effort of the row and one `--add-dir` per directory; `${API_JUDGE_CODEX:-codex}` for `openai` (base URL `https://api.openai.com/v1`) and `agentrouter` (`https://agentrouter.org/v1`), the provider's `env_key` being `DFORGE_JUDGE_KEY`. The flags C11 fixes are not optional: `--bare` keeps the Anthropic run off the subscription login, `--tools Read,Grep,Glob` and `--sandbox read-only` are what keep a judge from writing or running commands outside `--cwd`, where the worktree snapshot cannot see it. Should Task 1's note record that the CLI now spells one of them differently, pass the spelling the note records and change that flag's name in the test's `after` call; the restriction itself stays. In this task the child is given the one variable its provider needs (`ANTHROPIC_API_KEY`, or `DFORGE_JUDGE_KEY`), set by `export` in the subshell that runs it. A key value is never written on a command line: arguments are visible in the process list.
   - The prompt is the text of `--prompt`, a blank line, and the paragraph `You cannot write files. Reply with the whole report as your answer.`
   - Outcome of a run: past its bound is `status=TIMEOUT exit=124 out=- … reason=timeout`, and the chain ends with exit 3. A non-zero exit is `status=FAILED exit=<n> out=- … reason=error`. Otherwise take the reply text from the fields C11 names; when its first non-blank line, `\r` stripped, is not `## Verdict` it is `FAILED exit=0 … reason=no-verdict`. Otherwise write the reply to `--report` (creating its directory) and print `status=OK exit=0 out=<the --report path as given> … reason=none`, exit 0. After a `FAILED` row the next row is tried; after the last row exit 3.
   - `spent=` is `0.0000` on every line in this task.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/api-judge.test.sh; timeout 600 bash plugins/dforge/tests/lanes.test.sh; timeout 600 bash plugins/dforge/tests/ladder.test.sh`
Expected: all three end `0 failed` (`ladder.test.sh` parses every fenced block of `ladder.md`). The suite's `the timed-out CLI is stopped` check is what proves no hung stub is left: a hung stub has replaced itself with `sleep`, so a search by the stub's name would not find it.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/run-api-judge plugins/dforge/tests/fixtures/stub-api-judge plugins/dforge/tests/api-judge.test.sh plugins/dforge/reference/ladder.md plugins/dforge/tests/lanes.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): run rulings on API-billed judges"
```

### Task 6: `run-api-judge`: key hygiene, worktree proof and charging

**Files:**
- Modify: `plugins/dforge/scripts/run-api-judge`
- Test: `plugins/dforge/tests/api-judge.test.sh`

**Interfaces:**
- Consumes: C1, C5 (`api_budget_price`, `api_budget_charge`), C10, C11, `dr_snapshot` and `dr_task_assert_snapshot` of `plugins/dforge/scripts/lib/worktree-snapshot.sh`.
- Produces: C10's `spent=` amounts, the reasons `wrote` and `key-in-reply`, and the child environment the Keys section of the spec promises.

**Items:** 4, 5
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8
**Lenses:** security

- [ ] **Step 1: Write the failing test**

Read the `## Results` section of `docs/dforge/notes/2026-11-14-api-judge-cli-check.md` first. The code below assumes all three rows of C9. Where the note disproves a CLI, Task 5 left its rows out of the block and the `ladder` fixture, and this task's checks follow the rows that remain, by these rules:

- A check whose subject is a removed budget is dropped: for a disproved Codex CLI, the `for b in openai agentrouter` loop, the Codex half of each A16 check and both timed-out Codex checks; for a disproved Claude CLI, the three `A9: the Anthropic child` checks and the Anthropic half of each A16 check.
- In an expected string, the triple `<budget> <STATUS> <reason>` of a removed budget is removed, and a run whose only verdict came from a removed budget expects exit 3 and an `absent` report.
- `fixture: all three children ran` expects the number of rows that remain.
- A mode variable that steered a removed budget (`STUB_JUDGE_<BUDGET>=…`) is dropped from its `run` line; a check that only makes sense with a later budget to hand on to keeps its first triple and expects exit 3.

Name each check changed or dropped in the commit body.

In `plugins/dforge/tests/api-judge.test.sh`, insert these sections directly above the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- A9: what a judge child is given ---
sha() { printf '%s' "$1" | sha256sum | cut -c1-16; }
envof() { awk -v b="budget $1" '$0 == b { f = 1; next } f && $0 == "--" { exit } f' "$TMP/env.log"; }
holds() { # holds <budget> <value…> — how many of the child's variables hold one of the values
  local budget=$1 n=0 value; shift
  for value in "$@"; do n=$(( n + $(envof "$budget" | grep -c " $(sha "$value")\$") )); done
  echo "$n"
}
ALL_KEYS=(sk-test-anthropic-SENTINEL sk-test-openai-SENTINEL sk-test-agentrouter-SENTINEL vendor-openai vendor-anthropic)
fresh; caps 1000 1000 1000; ladder 30
run OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic CODEX_HOME="$TMP/user-codex" STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail
check "fixture: all three children ran" "$(started)" "3"
lacks "A8: no key value is on a judge's command line" "$(cat "$TMP/args.log")" "SENTINEL"
check "A9: the Anthropic child holds no DFORGE key variable" "$(envof anthropic | grep -c '^DFORGE_[A-Z]*_API_KEY ')" "0"
check "A9: the Anthropic child's ANTHROPIC_API_KEY is the DFORGE key, not the vendor variable's value" "$(envof anthropic | grep '^ANTHROPIC_API_KEY ')" "ANTHROPIC_API_KEY $(sha sk-test-anthropic-SENTINEL)"
check "A9: the Anthropic child holds one key, its own" "$(holds anthropic "${ALL_KEYS[@]}")" "1"
for b in openai agentrouter; do
  check "A9: the $b child holds no DFORGE key variable" "$(envof "$b" | grep -c '^DFORGE_[A-Z]*_API_KEY ')" "0"
  check "A9: the $b child holds no Anthropic key variable" "$(envof "$b" | grep -c '^ANTHROPIC_API_KEY ')" "0"
  check "A9: the $b child holds one key, its own" "$(holds "$b" "${ALL_KEYS[@]}") $(holds "$b" "sk-test-$b-SENTINEL")" "1 1"
  home=$(envof "$b" | sed -n 's/^CODEX_HOME //p')
  check "A9: the $b child's CODEX_HOME is not the user's" "$(case "$home" in unset | "$TMP/user-codex" | "$HOME/.codex") echo shared ;; *) echo own ;; esac)" "own"
done

# --- A8: a reply holding a key value is discarded ---
fresh
run STUB_JUDGE_ANTHROPIC=leak STUB_JUDGE_LEAK=sk-test-openai-SENTINEL
check "A8: a reply holding a key is FAILED key-in-reply and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED key-in-reply openai OK none "
lacks "A8: the report holds no key" "$(cat "$REPORT")" "SENTINEL"
run STUB_JUDGE_ANTHROPIC=leak STUB_JUDGE_LEAK=sk-test-agentrouter-SENTINEL STUB_JUDGE_OPENAI=fail STUB_JUDGE_AGENTROUTER=fail
check "A8: a reply holding a key is never written to the report" "$rc $(report)" "3 absent"

# --- A15: the worktree must not change during a run ---
fresh
for mode in write commit; do
  run "STUB_JUDGE_ANTHROPIC=$mode"
  check "A15: a run during which a $mode happened is FAILED wrote and ends the chain" "$rc $(tried)$(started)" "3 anthropic FAILED wrote 1"
  check "A15: after a $mode the reply is not written" "$(report)" "absent"
  rm -f "$WORK/stray.txt"
done
run STUB_JUDGE_ANTHROPIC=write-ignored
check "A15: a change git ignores is not a write" "$rc $(tried)" "0 anthropic OK none "

# --- A16: what a run cost is charged to its budget ---
spent() { bash "$SPEND" status | tr -d '\r' | sed -n "s/^api-budget $1 .* spent=\([0-9.]*\) .*/\1/p"; }
fresh; run
check "A16: the Anthropic run is charged the cost its CLI reports" "$(spent anthropic) $(status_lines | sed 's/.* spent=\([0-9.]*\) .*/\1/')" "0.2500 0.2500"
fresh; run STUB_JUDGE_ANTHROPIC=fail
check "A16: a run that reported nothing is charged 1.00, a Codex run is priced from its tokens" "$(spent anthropic) $(spent openai)" "1.0000 2.5000"
fresh; run STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
check "A16: a failed run is charged what it reported, agentrouter from the same table" "$(spent anthropic) $(spent openai) $(spent agentrouter)" "0.2500 2.5000 2.5000"
fresh; ladder 2
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang-usage
check "A16: a timed-out run is charged its last token total" "$(tried)$(spent openai)" "anthropic FAILED error openai TIMEOUT timeout 2.5000"
stopped() { kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped; }
check "A13: a timed-out Codex CLI that had reported usage is stopped" "$(stopped)" "stopped"
fresh
run STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang
check "A16: a timed-out run that reported nothing is charged 1.00" "$(spent openai)" "1.0000"
check "A13: a timed-out Codex CLI is stopped" "$(stopped)" "stopped"
ladder 30
fresh; run STUB_JUDGE_ANTHROPIC=silent
check "A16: a verdict with no cost reported is still charged 1.00" "$rc $(spent anthropic)" "0 1.0000"
fresh; caps 0 0 0; run
check "A16: a skipped budget is charged nothing" "$(spent anthropic)" "0.0000"
caps 1000 1000 1000

# --- a charge that cannot be recorded does not undo a ruling ---
fresh
LOCKBASE=$( . "$P/scripts/lib/lock.sh"; dr_lock_base "$HOME/.dforge/api-spend.json" )
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$$" > "$LOCKBASE.lockd/pid"
: > "$TMP/err"
run DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3
rm -rf "$LOCKBASE.lockd"
check "a charge that fails leaves the ruling and its status line standing" "$rc $(tried)$(report)" "0 anthropic OK none present"
has "a charge that fails is reported on stderr" "$(cat "$TMP/err")" "run-api-judge: the charge to anthropic was not recorded"
check "a charge that fails records nothing" "$(spent anthropic)" "0.0000"

# --- A8: no key value anywhere ---
lacks "A8: no key value in stdout, stderr, the log, the spend file or the state directory" \
  "$(cat "$TMP/all.out" "$TMP/err" "$JLOG" "$HOME/.dforge/api-spend.json" 2>/dev/null; grep -rh SENTINEL "$STATE" 2>/dev/null)" "SENTINEL"
```

The token arithmetic behind `2.5000`: the stub reports 1,000,000 input tokens of which 200,000 were cached, and 100,000 output tokens; at the fixture's prices (input 2, cached input 0.5, output 8 per million) that is `0.8 * 2 + 0.2 * 0.5 + 0.1 * 8`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/api-judge.test.sh`
Expected: Task 5's checks pass; the new `A9`, `A8`, `A15` and `A16` checks fail, except `A15: a change git ignores is not a write`, the Anthropic child's own-key checks and `A16: a skipped budget is charged nothing`, which may already pass.

- [ ] **Step 3: Implement**

All changes are in `plugins/dforge/scripts/run-api-judge`.

1. **The child's environment.** The subshell that runs a judge first unsets `DFORGE_OPENAI_API_KEY`, `DFORGE_ANTHROPIC_API_KEY`, `DFORGE_AGENTROUTER_API_KEY`, `OPENAI_API_KEY` and `ANTHROPIC_API_KEY`, then exports the one variable its provider reads, holding the budget's key: `ANTHROPIC_API_KEY` for `anthropic`, `DFORGE_JUDGE_KEY` for the two Codex budgets. The script reads the key into a shell variable before the subshell starts. No key value appears in any argument, any printed line, or any file the script keeps.
2. **Codex's home.** A Codex child's `CODEX_HOME` is a directory the script creates for that run inside its temporary directory, with mode 700, removed by the script's exit trap. It is never `$HOME/.codex` and never an inherited `CODEX_HOME`. The provider is configured only through the `-c` overrides of C11.
3. **The worktree proof.** Before a run starts, `dr_snapshot "$cwd" <file>` (from `lib/worktree-snapshot.sh`) into the temporary directory; when the run has ended, whatever its status, `dr_task_assert_snapshot <file>`. A change (return 1), or a snapshot that cannot be taken or compared (return 2), makes the run `status=FAILED exit=<the CLI's exit> out=- … reason=wrote`: its reply is discarded and the chain ends with exit 3, no further row tried. A run that timed out keeps `TIMEOUT`. The snapshot ignores what git ignores, so the report file and the log, both under the state root, do not count.
4. **The reply scan.** Before a reply is tested for its verdict, compare it against each non-empty value of the three `DFORGE_*_API_KEY` variables with a shell pattern match (`case "$reply" in *"$value"*`), not an external command. A hit is `status=FAILED exit=0 out=- … reason=key-in-reply`: the reply and the run's capture files are deleted at once, nothing of the reply is printed, and the next row is tried.
5. **Order.** For a run that ended inside its bound the first of these that holds decides its line: `wrote`, `key-in-reply`, `error` (non-zero exit), `no-verdict`, else `OK`.
6. **Charging.** After every run that started, whatever its status, work out its cost and call `api_budget_charge <budget> <usd>`; the line's `spent=` is that amount with four decimals. For `anthropic`, the cost is the cost field C11 names in the CLI's JSON output. For `openai` and `agentrouter`, take the last usage totals in the event stream the run wrote (the stream goes to a file as it arrives, so a timed-out run's totals are there): `(input - cached_input) * price(input) + cached_input * price(cached_input) + output * price(output)`, divided by one million, the cached price falling back to the input price when the table has none. A run for which no cost and no usage was found is charged `1.0000`. A `SKIPPED` row is charged nothing and prints `spent=0.0000`. A charge that fails (`api_budget_charge` returns nonzero: the spend file's lock could not be had) prints `run-api-judge: the charge to <budget> was not recorded` on stderr and changes nothing else (C5): the status line, its `spent=` amount, the report and the exit code stand.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/api-judge.test.sh`
Expected: ends `0 failed`; its three `is stopped` checks prove no hung stub is left running.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/run-api-judge plugins/dforge/tests/api-judge.test.sh
git commit -m "feat(dforge): scrub, prove and charge API judge runs"
```

### Task 7: Point the auto-run ladder at the new rungs

**Files:**
- Modify: `plugins/dforge/reference/auto-run.md` (§Rulings, and the final-message sentence under §Finishing)
- Modify: `plugins/dforge/skills/executing-plans/references/ruling-seat.md`
- Modify: `plugins/dforge/skills/writing-plans/references/auto-run-plan.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (§Auto run)
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: C7 (`decide ask`, `decide record`), C10 (`run-api-judge`, its exit codes and its background-call rule), C4 (`api-spend status`).
- Produces: the ladder text an auto run follows. Its tests decide A31; A19 and A30 are `demo` statements about a run that follows this text, and Task 10 Step 3 demonstrates both and keeps the evidence.

**Items:** 1, 4, 5
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/auto-run-skills.test.sh::the ruling ladder starts at the API rungs`**

Insert this section directly above the final `printf '\n%d passed, %d failed\n'` line:

```bash
# --- the ruling ladder starts at the API rungs ---
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
PLAN_REF="$P/skills/writing-plans/references/auto-run-plan.md"
check "A31: auto-run-plan.md does not name the Opus seat" "$(grep -c 'dforge:judge-opus' "$PLAN_REF")" "0"
check "A31: auto-run-plan.md sends a planning choice up the ladder from its first rung" \
  "$(flat "$PLAN_REF" | grep -cF 'goes up the ladder in auto-run.md §Rulings, from its first rung.')" "1"
rulings=$(awk '/^## Rulings/ { f = 1; next } f && /^## / { exit } f' "$R")
line_of() { printf '%s\n' "$rulings" | grep -nF -- "$1" | head -1 | cut -d: -f1; }
pending=$(line_of '**The pending list.**')
check "A31: the Rulings section has a pending-list rung" "$([ -n "$pending" ] && echo yes || echo no)" "yes"
for rung in 'scripts/decide ask' 'scripts/run-api-judge'; do
  at=$(line_of "$rung")
  check "A31: $rung comes before the pending list" "$([ -n "$at" ] && [ "$at" -lt "${pending:-0}" ] && echo yes || echo no)" "yes"
done
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: the two `auto-run-plan.md` checks and the two `comes before the pending list` checks fail; the pending-list check passes.

- [ ] **Step 3: Implement**

The four files are prose a session follows, so the text is given. Wrap it to the file's line width. The text names no budget, so a row that Task 1 removed from the `api-judge` block changes nothing here. If the block holds no row at all, stop and report that to the ruling seat as a discovered issue: rung 2 would be dead text.

1. `plugins/dforge/reference/auto-run.md` §Rulings. Replace the sentence `The ladder for anything you would have asked:` and rung `1. **Opus.**` (through the line ending ``or `no ruling`.`` that closes it) with the text below, and renumber `**The pending list.**` to 3 and `**Fable, in one batch.**` to 4. Leave every other paragraph of the section as it is.

   ```markdown
   The ladder for anything you would have asked. The `scripts/decide` and
   `scripts/run-api-judge` calls of rungs 1 and 2 are made only on Claude Code:

   1. **The Decisions API, for a choice item.** A choice item is a spec or
      planning choice before execution: a question with its options, your
      recommendation first. Run

          scripts/decide ask --id <id> --question "<q>" --options "<recommended | other>" --evidence <the spec> [--evidence <the plan>] [--evidence <a file the question names>]...

      On exit 0 the printed ruling stands: record it with
      `scripts/auto-run ruling add "Decisions API: <item> — <ruling>"`. On
      exit 3 go on to rung 2. An acceptance statement rated below `high` is
      not a choice item and starts at rung 2. An item a judge has declined to
      rule never returns to this rung.
   2. **Opus, on an API budget first.** During execution, the ruling seat
      (`dforge:judge-opus`) as the execution skills dispatch it; CONFIRMED-GAP,
      PARK and AMEND are carried out as always. Before execution (a spec or
      planning choice), the seat is given the question, its options with your
      recommendation first, the spec's path and the plan's path when one
      exists; it is asked for `ruling: <choice> — <reason>` or `no ruling`,
      told the report file `<state>/rulings-preexec-<k>-report.md` (`<k>` the
      next unused number) and to write nothing else, and to reply in at most
      10 lines; the report opens with `## Verdict` holding
      `ruling: <choice> — <reason>` or `no ruling`.

      Either way, a ruling the route gives to `dforge:judge-opus` goes to an
      API-billed judge first. Write the prompt the seat would get to a file
      under `<state>` and run, as a background Bash call with `timeout`
      2520000 and its output neither piped nor redirected:

          scripts/run-api-judge --prompt <file> --report <the report file> --cwd <the worktree> [--add-dir <dir>]...

      with one `--add-dir` for each directory outside the worktree that the
      prompt points at (the workspace holding the items file, ledger and
      amendments, and the documents root). Then end the turn and wait for its
      notification. Until it ends, change nothing under `--cwd` that git does
      not ignore, and run no git command there that changes its index or
      HEAD: a change voids the paid run. On exit 0 read the report's
      `## Verdict` as the seat's. On exit 3 dispatch `dforge:judge-opus`
      yourself, as above. Three rulings skip `scripts/run-api-judge` and go to
      the subscription seat directly: a `preflight` ruling, the fresh dispatch
      after `plan-amend` rejects an AMEND, and the independent confirmation
      of a Header amendment. A ruling the route gives to
      `dforge:judge-sonnet-high` is dispatched as today.

      When `decisionApi` is `shadow` and this rung ruled a choice item, run
      `scripts/decide record --id <id> --ruling "<the option it chose, or other>"`.
   ```

   In the pending-list rung, `An Opus `BLOCKED` or `no ruling`` stays as written: an API-billed judge's verdict is read as the seat's.
2. The same file, the sentence under §Finishing that begins ``Its final message lists every `Ruling:` ledger line``: add this item to its list, after the item on `scripts/auto-run ruling list`:

   ```markdown
   every line of `scripts/api-spend status`,
   ```

   and directly after that sentence add this one:

   ```markdown
   It names each of `decisionApi`, the three `apiBudget` caps and the three
   `DFORGE_*_API_KEY` variables that is still off, 0 or unset.
   ```
3. `plugins/dforge/skills/executing-plans/references/ruling-seat.md`: directly after the paragraph that says which seat rules (it ends by naming `dforge:judge-opus` as the seat otherwise), add:

   ```markdown
   **In an auto run on Claude Code,** a ruling the route gives to
   `dforge:judge-opus` goes to an API-billed judge first, as
   [auto-run.md](../../../reference/auto-run.md) §Rulings rung 2 says: write
   the seat's prompt to a file, start `scripts/run-api-judge` with it and the
   seat's report path as a background call, end the turn, and change nothing
   in the worktree until it ends. Exit 0: the report is the seat's verdict.
   Exit 3: dispatch the seat as below. A `preflight` ruling, the fresh
   dispatch after `plan-amend` rejects an AMEND, and a Header amendment's
   confirmation skip it and go to the seat directly.
   ```

4. `plugins/dforge/skills/writing-plans/references/auto-run-plan.md`: replace the bullet

   ```markdown
   - **An approach or planning choice** you would ask about goes to
     `dforge:judge-opus` first, then the ladder in auto-run.md §Rulings.
     dforge:selecting-approaches runs as usual otherwise.
   ```

   with

   ```markdown
   - **An approach or planning choice** you would ask about goes up the ladder
     in auto-run.md §Rulings, from its first rung.
     dforge:selecting-approaches runs as usual otherwise.
   ```

5. `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` §Auto run: in the bullet that says Step 7's final message lists every line of `scripts/auto-run ruling list` and every deferred row, add:

   ```markdown
   It also carries every line of `scripts/api-spend status`, and names each of
   `decisionApi`, the three `apiBudget` caps and the three `DFORGE_*_API_KEY`
   variables that is still off, 0 or unset.
   ```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/auto-run-skills.test.sh; timeout 600 bash plugins/dforge/tests/settings-skills.test.sh; timeout 60 node scripts/validate-repository.mjs`
Expected: both suites end `0 failed` and the validator passes. Then `rg -n "judge-opus. first" plugins/dforge/skills plugins/dforge/reference` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/auto-run.md plugins/dforge/skills/executing-plans/references/ruling-seat.md plugins/dforge/skills/writing-plans/references/auto-run-plan.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "feat(dforge): start auto-run rulings at the API rungs"
```

### Task 8: Cockpit keep-warm

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/reference/session-budget.md` (§Idle)
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Modify, only on the third outcome of the draft check: `plugins/dforge/config/schema.mjs` and `plugins/dforge/tests/dforge-config.test.sh` (`keepWarm` default 0)

**Interfaces:**
- Consumes: C2 (`keepWarm`), C12.
- Produces: the keep-warm rule of the cockpit watchdog (A21 to A24, A29).

**Items:** 2
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Before the tests, make the draft check the spec requires first. Load the `plugin-authoring` skill and find what a mod test offers for the prompt composer: a way to put text into it and a way to read it back. In a scratch test file that is not committed, start a session, put a half-typed draft into the composer, call `$.prompt.submit({ text: 'x', asUser: true })`, and read the composer. One of three outcomes holds, and it decides one thing below:

- **safe**: the draft is unchanged, or the engine offers no composer at all to a mod and its documentation says a submit does not touch the person's draft. Ship the rule as written, default 50.
- **guarded**: the draft is disturbed and the engine reports the composer's text. Ship the rule with one more condition, no prompt while the composer holds text, and add the last test below.
- **off**: the draft is disturbed, or nothing can be learned about it, and the composer cannot be read. Ship the rule with default 0: in `config/schema.mjs` `keepWarm` gets `default: 0`, the `ROWS` line in `tests/dforge-config.test.sh` becomes `keepWarm 0 4 60`, and the cockpit's own default becomes 0.

Write down which outcome held and what was observed; Step 5's commit body carries it (A29).

In `plugins/dforge/tests/cockpit.test.ts`, add this block directly after the closing `})` of `describe('a Done held for background work', …)`, inside the same enclosing `describe`, where `SHELL`, `ENDED`, `notified` and `WEBHOOK` are in scope:

```ts
  describe('keep-warm', () => {
    const KEEP_WARM =
      'Keep-warm: background work is still running and the prompt cache is about to expire. Reply with the single line `Still waiting.` and end the turn. Start nothing and call no tool.'
    const MIN = 60_000
    const quiet = (config: Record<string, unknown>): World => ({ tokens: 50_000, prompts: [], config, tools: { Bash: () => SHELL } })
    const sentOf = (w: World) => (w.prompts ?? []).filter(one => one === KEEP_WARM)
    // A turn that sends a command to the background and ends, the command still running.
    const begin = async ($: Parameters<TestBody>[0], command = 'npm test') => {
      await $.session.start(START)
      await $.turn.start({ text: 'run it', turnId: 't1' })
      await $.tool.call({ tool: 'Bash', command, run_in_background: true } as never)
      await $.turn.complete({ answer: 'Started it.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    }
    // The turn the cockpit's own prompt starts.
    const keepWarmTurn = async ($: Parameters<TestBody>[0], clock: ReturnType<typeof world>, turnId: string) => {
      await $.turn.start({ text: '', turnId })
      await clock.advance(2_000)
      await $.turn.complete({ answer: 'Still waiting.', durationMs: 2_000, isAborted: false, turnId, reason: 'answer' })
    }

    test('submits the prompt once keepWarm minutes pass with background work running, and again each further interval', async ($, on) => {
      const w = quiet({ keepWarm: 50 })
      const clock = world(on, w)
      await begin($)
      await clock.advance(49 * MIN)
      expect(sentOf(w)).toHaveLength(0)
      await clock.advance(2 * MIN)
      expect(sentOf(w)).toHaveLength(1)
      await keepWarmTurn($, clock, 'k1')
      await clock.advance(48 * MIN)
      expect(sentOf(w)).toHaveLength(1)
      await clock.advance(3 * MIN)
      expect(sentOf(w)).toHaveLength(2)
    })

    test('submits nothing when keepWarm is 0', async ($, on) => {
      const w = quiet({ keepWarm: 0 })
      const clock = world(on, w)
      await begin($)
      await clock.advance(180 * MIN)
      expect(sentOf(w)).toHaveLength(0)
    })

    test('submits nothing when only a service command runs in the background', async ($, on) => {
      const w = quiet({ keepWarm: 50 })
      const clock = world(on, w)
      await begin($, 'npm run dev')
      await clock.advance(120 * MIN)
      expect(sentOf(w)).toHaveLength(0)
    })

    test('submits nothing when no background work runs', async ($, on) => {
      const w = quiet({ keepWarm: 50 })
      const clock = world(on, w)
      await $.session.start(START)
      await $.turn.start({ text: 'hello', turnId: 't1' })
      await $.turn.complete({ answer: 'Hello.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await clock.advance(120 * MIN)
      expect(sentOf(w)).toHaveLength(0)
    })

    test('submits nothing while a turn is live', async ($, on) => {
      const w = quiet({ keepWarm: 50 })
      const clock = world(on, w)
      await begin($)
      await $.turn.start({ text: 'and the docs?', turnId: 't2' })
      await clock.advance(120 * MIN)
      expect(sentOf(w)).toHaveLength(0)
    })

    test('submits nothing while an auto run is bound to the session', async ($, on) => {
      const files = autoFiles({ pending: null })
      const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: { Bash: () => SHELL } }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.tool.call({ tool: 'Bash', command: 'npm test', run_in_background: true } as never)
      await $.turn.complete({ answer: 'Waiting.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await clock.advance(120 * MIN)
      expect(sentOf(w)).toHaveLength(0)
      expect(w.prompts?.length).toBeGreaterThan(0)
    })

    for (const origin of ['composer', 'task-notification'] as const)
      test(`stops after six in a row, and a ${origin} turn lets six more go`, async ($, on) => {
        const w = quiet({ keepWarm: 4 })
        const clock = world(on, w)
        await begin($)
        for (let i = 1; i <= 8; i++) {
          await clock.advance(5 * MIN)
          if (sentOf(w).length === i) await keepWarmTurn($, clock, `k${i}`)
        }
        expect(sentOf(w)).toHaveLength(6)
        await $.prompt.submit({ text: 'status?', origin: { kind: origin }, wait: false } as never)
        await $.turn.start({ text: 'status?', turnId: 'u1' })
        await $.turn.complete({ answer: 'Still running.', durationMs: 1, isAborted: false, turnId: 'u1', reason: 'answer' })
        await clock.advance(5 * MIN)
        expect(sentOf(w)).toHaveLength(7)
      })

    test('a keep-warm turn leaves the held Done in place and does not become its text', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const w: World = { ...quiet({ keepWarm: 4, notifyAfter: 0 }), fetches }
      const clock = world(on, w)
      mock.store(on, { notifyUrl: WEBHOOK })
      await begin($, 'node codex-companion.mjs review')
      await clock.advance(5 * MIN)
      expect(sentOf(w)).toHaveLength(1)
      await keepWarmTurn($, clock, 'k1')
      expect(fetches).toHaveLength(0)
      await $.session.append(notified(ENDED))
      await clock.advance(6_000)
      expect(fetches).toHaveLength(1)
      expect((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.description).toBe('Started it.')
    })

    test('a keep-warm turn sends no Done of its own', async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      const w: World = { ...quiet({ keepWarm: 50, notifyAfter: 0 }), fetches }
      const clock = world(on, w)
      mock.store(on, { notifyUrl: WEBHOOK })
      await begin($)
      await clock.advance(51 * MIN)
      expect(sentOf(w)).toHaveLength(1)
      const before = fetches.length
      await keepWarmTurn($, clock, 'k1')
      await clock.advance(10_000)
      expect(fetches).toHaveLength(before)
    })
  })
```

On the **guarded** outcome only, add one more test inside that `describe`. It gives `World` a field `draft?: string` and makes `world()` answer the engine's composer read (the call the draft check found) with `w.draft ?? ''`:

```ts
    test('submits nothing while the composer holds a draft', async ($, on) => {
      const w: World = { ...quiet({ keepWarm: 50 }), draft: 'half a sent' }
      const clock = world(on, w)
      await begin($)
      await clock.advance(120 * MIN)
      expect(sentOf(w)).toHaveLength(0)
      w.draft = ''
      await clock.advance(MIN)
      expect(sentOf(w)).toHaveLength(1)
    })
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: the `keep-warm` tests that expect a prompt fail (`sentOf(w)` stays empty), `a keep-warm turn sends no Done of its own` among them; the tests that expect nothing pass already.

- [ ] **Step 3: Implement**

All in `plugins/dforge/hooks/cockpit/register.tsx`. Every hook stays a top-level function: a mod does not load when a hook is a closure constant.

1. **The setting.** Add `keepWarm: number` to `type Options`, give it its default beside `notifyAfter = 60` in `liveFrom` (50, or 0 on the **off** outcome), and thread it wherever `notifyAfter` is threaded from the settings file, so `(await live($)).keepWarm` answers it.
2. **Constants.** `KEEP_WARM_CAP = 6` beside `RECONCILE_CAP`, and a top-level `keepWarmPrompt()` returning C12's text exactly.
3. **State**, beside `reconciledAt` in `S`, reset wherever `reconciledAt` is reset: how many keep-warm prompts were sent in a row, when the last was submitted, a mark that the cockpit has just submitted one, and a flag that the main turn now running is a keep-warm turn.
4. **The rule**, a top-level `async function keepWarm($)` called from `watchdogTick` at the point where it returns because no run is bound (`auto === null || !auto.active`): call it there, then return as today. It is never reached while a turn is live or `S.autoBusy` is set, because `watchdogTick` returns earlier. It submits `{ text: keepWarmPrompt(), asUser: true }` when all of these hold:
   - `keepWarm` minutes is above 0;
   - no approval or question is waiting on the person (`S.waits` holds none for the main loop);
   - `isMainBackground($)` is true;
   - at least `keepWarm` minutes have passed since the latest of the last main turn's end (`activity.endedAt`), the last keep-warm submit, and `S.watchedSince`;
   - fewer than `KEEP_WARM_CAP` have been sent in a row;
   - on the **guarded** outcome, the composer is empty.
   Before the submit it sets the mark, adds one to the count and stores the time; a submit that rejects takes the mark and the count back.
5. **The prompt.submit hook** (the one that drops `S.heldDone` for `NEW_CHAIN_ORIGINS`): a submit whose text is the keep-warm prompt while the mark is set drops nothing, though its origin is the plugin's. Any other submit clears the mark, so the turn it starts counts as another origin's.
6. **The main turn.start hook:** with the mark set, the turn is a keep-warm turn and the mark is cleared; without it, the count returns to 0 and the flag is cleared.
7. **The main turn.complete hook**, for a keep-warm turn that ended with `reason: 'answer'`: `S.heldDone` is left exactly as it was (not replaced, its `heldAt` not moved, its answer not changed), the activity is `background` when a Done is held and `idle` otherwise, `sendDone` is not called, and the flag is cleared. A keep-warm turn that failed or was aborted is handled as any turn.

Then `plugins/dforge/reference/session-budget.md` §Idle, a second paragraph:

```markdown
While the session waits on background work outside an auto run, the cockpit
keeps the cache warm: after `keepWarm` minutes (default 50, 0 off) with no
main turn, it submits a one-line prompt that the session answers with
`Still waiting.`, at most six in a row. A turn of any other origin starts the
count again. Set `keepWarm` to 4 on the five-minute cache. A wait inside a
live turn cannot be kept warm, and in an auto run the reconcile prompt
already gives the session a turn every 20 minutes.
```

On the **off** outcome the paragraph says `default 0, off` and names the reason in one sentence.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge; timeout 600 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: every cockpit test passes, the earlier `a Done held for background work` and `auto run` tests included; the config suite ends `0 failed`.

- [ ] **Step 5: Commit**

The body states the draft check's outcome (`safe`, `guarded` or `off`) and what was observed.

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts plugins/dforge/reference/session-budget.md plugins/dforge/config/schema.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "feat(dforge): keep the prompt cache warm while waiting"
```

### Task 9: Measure Hydrogen and place it in the agy roster

**Files:**
- Create: `docs/dforge/notes/2026-11-14-agy-hydrogen-review.md`
- Modify: `plugins/dforge/reference/agy-policy.json` (`calibrated`; `min_version` on a Hydrogen verdict)
- Modify: `plugins/dforge/tests/lanes.test.sh` (the fallback-row pin), `plugins/dforge/tests/agy-gate.test.sh` (the policy pin)
- Modify, on a Hydrogen verdict only: `plugins/dforge/reference/ladder.md` (last `agy-judge` row and the prose that names Argon), `plugins/dforge/reference/external-review.md`, `plugins/dforge/reference/delegated-task.md`, `plugins/dforge/README.md`, `plugins/dforge/tests/agy-review.test.sh`, `plugins/dforge/tests/review-panel.test.sh`, `plugins/dforge/tests/reviewer-only-externals.acceptance.test.sh`

**Interfaces:**
- Consumes: nothing from an earlier task.
- Produces: C13.

**Items:** 3
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 0 - risk 2 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/lanes.test.sh::agy-judge fallback row`**

Replace the line

```bash
check "agy-judge fallback row" "$(printf '%s\n' "$agy" | sed -n 2p)" "gemini-4-argon high 2400"
```

with

```bash
# The fallback row follows the measurement note's verdict (docs/dforge/notes). The note
# records one measurement and is not edited afterwards: a later roster change replaces
# these checks with a literal row.
NOTE="$P/../../docs/dforge/notes/2026-11-14-agy-hydrogen-review.md"
verdict=$(grep '^Verdict: ' "$NOTE" 2>/dev/null | tail -1 | tr -d '\r')
vmodel=$(printf '%s\n' "$verdict" | awk '{print $2}'); veffort=$(printf '%s\n' "$verdict" | awk '{print $3}')
measured=$(sed -n 's/^agy version: //p' "$NOTE" 2>/dev/null | head -1 | tr -d '\r')
check "the measurement names Hydrogen or Argon" "$(case "$vmodel" in gemini-4-hydrogen | gemini-4-argon) echo yes ;; *) echo "no: [$verdict]" ;; esac)" "yes"
check "the note's Verdict line is its last line" "$(tail -1 "$NOTE" 2>/dev/null | tr -d '\r')" "$verdict"
check "A27: the agy-judge fallback row follows the verdict" "$(printf '%s\n' "$agy" | sed -n 2p)" "$vmodel $veffort 2400"
check "A27: calibrated is the agy version the runs used" "$(jq -r '.calibrated' < "$P/reference/agy-policy.json" | tr -d '\r')" "$measured"
if [ "$vmodel" = gemini-4-hydrogen ]; then
  check "A27: a Hydrogen verdict raises min_version to that version" "$(jq -r '.min_version' < "$P/reference/agy-policy.json" | tr -d '\r')" "$measured"
fi
```

The existing check `agy-judge preferred row` (`claude-opus-5-5 high 5400`) stays as it is: it is A28.

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/lanes.test.sh`
Expected: three of the new checks fail (the note does not exist yet): `the measurement names Hydrogen or Argon`, `A27: the agy-judge fallback row follows the verdict` and `A27: calibrated is the agy version the runs used`. `the note's Verdict line is its last line` compares two empty strings and passes. The rest pass.

- [ ] **Step 3: Measure**

Nothing here runs in the real checkout, names a Claude model, or passes `--dangerously-skip-permissions`. Only Gemini quota is spent: ten runs.

1. `timeout 60 agy --version` and `timeout 60 agy models`. Both `gemini-4-hydrogen` (with `high` and `xhigh`) and `gemini-4-argon` (`high`) must be listed. If `agy` is missing, signed out, or a model is not listed, stop: the task is BLOCKED with that as its reason.
2. Make a scratch directory `S` under the session's scratchpad directory (`mktemp -d` when the session has none) and `git clone --no-hardlinks /root/repositories/darkraise-ai-plugins "$S/repo"`.
3. Pick three branches: from `git -C "$S/repo" log --merges --first-parent --format=%H -n 40 main`, the three most recent merges for which `git diff --shortstat <merge>^1...<merge>^2 -- plugins` reports at least 200 changed lines. For each, `base=$(git merge-base <merge>^1 <merge>^2)` and `git -C "$S/repo" worktree add --detach "$S/b<k>" <merge>^2`.
4. `mkdir -p "$S/out" "$S/judge"` (the runner refuses an `--out` whose directory does not exist). Write three fixture ladders in `S`, each a file holding one fenced `agy-judge` block with one row: `gemini-4-argon high 2400`, `gemini-4-hydrogen high 2400`, `gemini-4-hydrogen xhigh 2400`. Write a gate stub `S/gate` that prints the line `agy-gate usable=true reason=ok review=true resets_at=- claude=off claude_resets_at=- source=setting` (the format `scripts/agy-gate` documents in its header), so the measurement does not depend on the `agyReview` setting and never routes to a Claude model.
5. Nine runs, as background Bash calls with `timeout` 2520000, at most three at once and never two in one worktree: for each ladder and each branch,
   `AGY_REVIEW_LADDER="$S/<ladder>.md" AGY_REVIEW_GATE="$S/gate" timeout 2500 bash "$S/repo/plugins/dforge/scripts/run-agy-review.sh" --kind final --cwd "$S/b<k>" --out "$S/out/<model>-<effort>-b<k>.json" --base <base>`.
   Keep each run's status line and wall time. A run whose status is not `OK`, or whose output file holds no findings list, is not usable.
6. Copy the usable lists to `S/judge/list-01.json` … in an order drawn with `shuf`, and keep the mapping in `S/mapping.txt`, which the judge is not given. Dispatch `dforge:judge-opus` once, with the working directory in the real checkout: it is given the three worktrees with their base commits, each list with the worktree it reviews, and the task of reading the code and marking every finding `confirmed` (a real defect of that diff) or `unconfirmed`; it writes only `<state>/hydrogen-judging-report.md`, whose `## Verdict` section holds one line per list: `list-<nn>: <findings> findings, <confirmed> confirmed`. The prompt names that report path and does not name any model.
7. Apply the spec's rule with the mapping. Hydrogen's effort is the one with more confirmed findings over the three branches, `high` on a tie. Then one more run, on `b1`, with that ladder:
   `AGY_REVIEW_LADDER="$S/<that ladder>.md" AGY_REVIEW_GATE="$S/gate" timeout 2500 bash "$S/repo/plugins/dforge/scripts/run-agy-review.sh" --kind task --tier light --cwd "$S/b1" --out "$S/out/task-b1.json" --prompt "$S/task-prompt.md"`,
   the prompt asking for a review of `git diff <base>..HEAD` against the merge commit's subject as the requirement. Hydrogen replaces Argon when, at that effort, all three final runs and the task run were usable, its confirmed total is at least Argon's, its unconfirmed share (unconfirmed over findings, in percent) is at most Argon's plus 10 points, and its slowest run finished inside 2400 seconds. Otherwise Argon stays.
8. Write `docs/dforge/notes/2026-11-14-agy-hydrogen-review.md`: the date, the line `agy version: <x.y.z>`, the three merges and bases, a table of the ten runs (model, effort, branch, kind, status, seconds, findings, confirmed), both models' confirmed totals and unconfirmed shares, the rule's four conditions each with its value and pass or fail, and as its last line `Verdict: <model> <effort>` (`Verdict: gemini-4-argon high` when Argon stays).
9. Remove the worktrees and the scratch directory, and confirm with `pgrep -fl agy` that no agy process of this task is left.

- [ ] **Step 4: Place the result**

1. `plugins/dforge/reference/agy-policy.json`: `calibrated` becomes the measured agy version. On a Hydrogen verdict `min_version` becomes it too. Update the pin in `plugins/dforge/tests/agy-gate.test.sh` (the check `the policy states the cli, the version floor, the major ceiling and the calibrated version`) to the new values.
2. On a Hydrogen verdict: the last row of the `agy-judge` block in `reference/ladder.md` becomes `gemini-4-hydrogen <effort> 2400`, and every `gemini-4-argon` with its effort in the files listed above becomes `gemini-4-hydrogen` with the verdict's effort (`rg -n "gemini-4-argon|Argon" plugins/dforge --glob '!docs/**'` finds them; the test files use the form `gemini-4-argon/high` and fixture ladders of their own). The prose in `ladder.md` that explains the Gemini row cites the note. The first row is not touched.
3. On an Argon verdict nothing else changes.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dforge/tests/lanes.test.sh; timeout 600 bash plugins/dforge/tests/agy-gate.test.sh; timeout 600 bash plugins/dforge/tests/agy-review.test.sh; timeout 600 bash plugins/dforge/tests/review-panel.test.sh; timeout 900 bash plugins/dforge/tests/reviewer-only-externals.acceptance.test.sh`
Expected: each ends `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add docs/dforge/notes/2026-11-14-agy-hydrogen-review.md plugins/dforge/reference plugins/dforge/README.md plugins/dforge/tests
git commit -m "feat(dforge): place Gemini Hydrogen by measurement"
```

### Task 10: Live checks and user-facing docs

**Files:**
- Modify: `docs/dforge/notes/2026-11-14-api-judge-cli-check.md` (`## Results`, `## Demos`)
- Modify: `plugins/dforge/README.md` (settings rows, an `API budgets` section)
- Modify: `SECURITY.md`

**Interfaces:**
- Consumes: C1, C4, C7, C10, C11.
- Produces: A20's evidence, or the record that it could not be gathered; and the demonstrations of A19 and A30 (the note's `## Demos` section).

**Items:** 4, 5
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

- [ ] **Step 1: No new test, because this task makes live, billed checks and writes documentation no script reads; the scripts it exercises are pinned by `plugins/dforge/tests/api-judge.test.sh::first open budget wins` and `plugins/dforge/tests/decide.test.sh::A1: a confident answer in both orders rules, at the lower confidence`**

- [ ] **Step 2: The live checks**

For each of `DFORGE_ANTHROPIC_API_KEY`, `DFORGE_OPENAI_API_KEY` and `DFORGE_AGENTROUTER_API_KEY`, test only whether it is set (`[ -n "${VAR:-}" ]`), never printing it. A variable that is unset makes its check `not run — <VARIABLE> unset`: record that and go on. The settings and the spend file used here are throwaway: every command below runs with `HOME` set to a new scratch directory holding only `.dforge/config.json`, and with the working directory in a scratch `git init` repository with one commit and a bound auto run (`scripts/auto-run --session <a made-up id> start --spec docs/s.md`, after writing that session's heartbeat file under the scratch `HOME`), so the real settings, the real spend file and the real run are not touched. The real `HOME` is passed only where a CLI needs its own files: none of these does.

A scratch `HOME` breaks two lookups, so every command of Steps 2 and 3 also runs with these two variables exported, set before `HOME` is changed:

- `AR_SESSION=<the made-up id>`. The scripts bind a run through `AR_SESSION` and fall back to `CLAUDE_CODE_SESSION_ID`, which holds this session's real id; without `AR_SESSION` every call ends `reason=no-run`.
- `API_JUDGE_CLAUDE=<the real HOME>/.local/bin/claude`. `claude` is a shell function in this shell, not a program on PATH, and the script's fallback `$HOME/.local/bin/claude` does not exist under the scratch `HOME`.

A run that ends `reason=no-run`, or fails because a CLI was not found, is a fault of this setup: fix the setup and repeat it. It is never recorded as a disproved CLI.

1. Before anything: `sha256sum ~/.codex/auth.json` (the real home), and `/root/.local/bin/claude auth status` or the equivalent line the CLI offers for the login in use.
2. One live ruling per budget whose key is set, the other two caps at 0, the cap of the one under test at 5: write a prompt asking for a report that opens with `## Verdict` and holds `ruling: yes — <one reason>` on whether `README.md` of the scratch repository has a first line, and run `scripts/run-api-judge --prompt <file> --report <scratch state>/live-<budget>-report.md --cwd <scratch repository>` as a background Bash call. Expected: `status=OK`, the report opens with `## Verdict`, and `scripts/api-spend status` shows that budget's `spent` above 0.
3. One live `scripts/decide ask` with `decisionApi` `shadow` and `apiBudgetOpenai` 5, a two-option question and the scratch spec as evidence. Expected: `no ruling reason=shadow`, and the last line of the scratch `decisions.jsonl` holds two choices and two confidences.
4. After: `sha256sum ~/.codex/auth.json` is unchanged, the Claude login line is unchanged, and this session is still on the subscription (its own status line or `/status` shows no API-key billing).
5. Write the results into the `## Results` section of `docs/dforge/notes/2026-11-14-api-judge-cli-check.md`: one line per budget and one for the Decisions request (`verified live <date>: …`, `failed: <the status line>`, or `not run — <VARIABLE> unset`), and the two before-and-after comparisons. A budget whose live ruling failed for a reason the CLI gives (not a missing key) is reported to the ruling seat as a discovered issue: its row may have to leave the `api-judge` block.

- [ ] **Step 3: Demonstrate A19 and A30**

Both are `demo` statements: the evidence is a transcript kept in the note, under a new heading `## Demos`, holding each command as run (keys by variable name only) and the lines it printed. Work in the scratch repository and scratch `HOME` of Step 2, with the same two variables exported, and follow the text of §Rulings in this worktree's `plugins/dforge/reference/auto-run.md` (the text Task 7 wrote), using this worktree's scripts.

1. **A19, a choice item.** Set `decisionApi` to `on` and `apiBudgetOpenai` to 5 in the scratch config. Make up one planning choice with two options and run rung 1's `scripts/decide ask --id demo-1 …` with the scratch spec as evidence. Record its one line. A `ruling:` line ends the item at rung 1. A `no ruling reason=<token>` line (`closed` when the OpenAI key is unset) sends the same item to rung 2, below.
2. **A19, a ruling routed to `dforge:judge-opus`.** Write the pre-execution prompt rung 2 describes for the same choice to `<scratch state>/demo-prompt.md`, and run `scripts/run-api-judge --prompt <that file> --report <scratch state>/rulings-preexec-1-report.md --cwd <scratch repository>` as a background Bash call, with the cap of one budget whose key is set at 5 and the others at 0. Record its `started` and `status=` lines and the report's `## Verdict` section. When no key is set, run it once with `API_JUDGE_CLAUDE=<worktree>/plugins/dforge/tests/fixtures/stub-api-judge/claude`, `apiBudgetAnthropic` at 5 and `DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL` in that one command's environment, and say in the transcript that the judge was the test stub.
3. **A19, the subscription seat only after exit 3.** Set every cap to 0 and run the same `scripts/run-api-judge` command again. Record its three `status=SKIPPED` lines and its exit code 3, and write below them: `exit 3 — the subscription seat is dispatched at this point, and not before`. Dispatch no seat: the ruling is made up.
4. **A30.** Run this worktree's `scripts/api-spend status` once under the scratch `HOME` and once under the real `HOME` (it only reads), and record both sets of three `api-budget` lines. Then add this line to the `## Gotchas` section of `<ledger dir>/handoff.md`, so the session that finishes the run carries it out: `Finishing: the final message carries the three lines of "bash plugins/dforge/scripts/api-spend status" run from the merged tree (spec A30), and names each of decisionApi, the three apiBudget caps and the three DFORGE_*_API_KEY variables that is still off, 0 or unset. The installed plugin has no such script yet.`
5. Remove the scratch directories.

- [ ] **Step 4: The docs**

1. `plugins/dforge/README.md`: in the settings reference, a row for each of the six new settings in the form the neighbouring rows use (name, default, what it does), and a section `### API budgets` near the auto-run documentation that says, in this order: what the three `DFORGE_*_API_KEY` variables are and that the vendors' own variable names are never read (and why: an exported `ANTHROPIC_API_KEY` moves the whole Claude Code session onto API billing); that everything is off until a cap is set and, for the Decisions API, `decisionApi` is `shadow` or `on`; the order the budgets are tried, which is the rows the `api-judge` block of `reference/ladder.md` holds at this point (a budget whose row Task 1 or Step 2 removed is named as not supported, with the reason), and that the subscription seat rules when none can; `scripts/api-spend status` and that the count covers only what dforge spent, so auto-recharge should be off in each vendor console; `scripts/decide report` and its `promote:` line as the way to judge `shadow` before `on`; and that `keepWarm` works outside an auto run only.
2. `SECURITY.md`: a section `## API keys and API-billed judges` stating the spec's Known limits in the reader's terms: the keys live in the shell profile and every process the session starts can read them; what dforge's scripts guarantee (the scrubbed child environment, the reply scan, no key in any output, log or argument); that a Codex judge can read any file the user can read and the Anthropic judge reads the worktree and its added directories, ignored files included; that AgentRouter is a third party through which the ruling prompt and every file its judge reads pass, off until its cap and key are set; and that only `scripts/decide` filters what it sends.

- [ ] **Step 5: Verify**

Run: `timeout 60 node scripts/validate-repository.mjs; timeout 60 /root/.local/bin/claude plugin validate plugins/dforge; rg -n "sk-[A-Za-z0-9]{12,}" docs/dforge/notes/2026-11-14-api-judge-cli-check.md plugins/dforge/README.md SECURITY.md`
Expected: both validators pass and the search prints nothing, or only the test sentinel `sk-test-anthropic-SENTINEL` of the stubbed demo: no real key value was written into a document.

- [ ] **Step 6: Commit**

```bash
git add docs/dforge/notes/2026-11-14-api-judge-cli-check.md plugins/dforge/README.md SECURITY.md
git commit -m "docs(dforge): document API budgets and keep-warm"
```
