# Free-model executors — capability survey

**Source:** owner request, 2026-09-21 and 2026-09-22 sessions: evaluate OpenCode
free models as a lane executor, then "any other coding cli with free models
worth investigating?"
**Covers:** items 1 to 3 of `registers/2026-09-20-opencode-executor.md`
**Recommendation:** do not build a free cloud executor into the lane. The
decision itself is the owner's and is not recorded here.

Provenance is labelled throughout. **Measured** means run against a binary on
this host during the session; **cited** means read from a vendor document or
issue tracker. Nothing here is from model memory — the area moved faster than
any training cutoff.

## Verdict in one paragraph

OpenCode Zen's free models work, cost nothing, and edit files correctly, but
their quota is unpublished and six of seven are labelled "limited time". Every
other vendor-operated free tier surveyed is dead, unmeasurable, or too small to
run one agentic loop. The lane gate admits totals 2 to 4 at risk 1 or less —
the band Claude already sends to Sonnet — and a failed offload costs a wrapper
run, a review seat, up to three fix rounds and then `HANDBACK` to the Claude
ladder anyway. That arithmetic does not survive an executor that fails often.

## What was measured on this host

| Tool | Version | Result |
|---|---|---|
| `opencode` | 1.18.23 | 0 credentials, yet `run` succeeds; free models usable |
| `gemini` | 0.58.0 | Installed, unauthenticated; headless run exits 41 |
| `scripts/executors list` | dr-superpowers 1.17.0 | `codex` only |

### OpenCode Zen

**Measured.** `opencode providers list` reports 0 credentials. A headless run
against `opencode/big-pickle` returned in 7 seconds, exit 0. Every
`step_finish` event carries `cost: 0` alongside token counts, and all six
catalogued models report `cost.input`, `cost.output` and `cost.cache` of 0 with
`toolcall: true` and contexts from 190k to 1M.

**Measured.** `nemotron-3.5-lightning-free` was given a two-file edit in a
scratch git repository: add a function to one file, import and call it in
another, change nothing else. It produced exactly the right diff in 5 read and
2 edit tool calls. It took **181 seconds** for work scoring about 1 on the
rubric; the lane admits 2 to 4.

**Measured — catalog churn.** The cached catalog listed `hy3-free`. After
`opencode models --refresh` within the same session, `hy3-free` was gone and
`ling-3.0-flash-fin-free` and `muse-spark-1.3-contributor-free` had appeared.
The vendor docs list a third set including `jev-1.13-free` and
`deepseek-v4-flash-free` present in neither. This matters mechanically:
`plan-lint:320` validates each `**Executor:**` line against the rung table for
the task's total, so a withdrawn model turns existing plans into lint errors.

**Cited.** Six of seven free models are "available on OpenCode for a limited
time". Users hit "Free usage exceeded, add credits"
([issue #28055](https://github.com/anomalyco/opencode/issues/28055),
2026-05-17, unanswered); no requests-per-minute, per-day or token cap is
published anywhere. `hy3-free` returns "your account balance is insufficient"
and `nemotron-3-ultra-free` an upstream provider error
([issue #38028](https://github.com/anomalyco/opencode/issues/38028),
2026-07-21, open). Rate limits are reported as tolerable for interactive
coding and painful for agentic loops that fan out dozens of tool calls.

**Capability.** Nemotron 3.5 Lightning is a 30B mixture-of-experts with 3B
active, scoring 51.56 on SWE-bench Verified (vendor self-reported). The lane
replaces `impl-sonnet-medium`, `impl-sonnet-high` and `impl-opus-low`.

## The 2026 consolidation

The single most important finding is that this is a pattern, not bad luck.
Free agentic inference was withdrawn across the board this year. All cited.

| What ended | When |
|---|---|
| Qwen Code free OAuth tier (cut 1,000 to 100 requests/day, then closed) | 2026-04-15 |
| iFlow CLI — whole product, API and model library | 2026-04-17 |
| Gemini CLI / Code Assist free personal login | 2026-06-18 |
| GitHub Models — playground, catalog, inference API, BYOK | 2026-07-30 |
| Google removed all numeric free-tier limits from the Gemini API docs | page stamped 2026-09-02 |
| Amp Free paused; Roo Code archived | 2026-05-15 (Roo) |

Google now states only that limits "depend on a variety of factors" and are
"not guaranteed". The surviving Gemini free tier therefore has the same
unpublished-quota problem that disqualified OpenCode Zen, plus terms that use
unpaid submissions to improve Google products with possible human review, and
a ban on free-tier use for users in the EEA, Switzerland and the UK.

Providers that fail on arithmetic rather than features: Groq at 8,000
tokens/minute against agentic turns of 20k to 100k tokens — the first call
fails, and 200k tokens/day is 2 to 10 requests total; SambaNova at 20
requests/day; Cerebras has no free tier at all ("Is there a permanently free
tier? No") and requires a verified payment method. Cerebras additionally
prohibits any tool sending "more request messages to the servers running the
Service than a human can reasonably produce".

The only free tier surveyed that publishes hard numbers is **OpenRouter**: 20
requests/minute, 50/day below 10 purchased credits, 1,000/day above, with no
token cap. Reaching the useful tier costs a one-time $10.

## CLI contracts, ranked for this lane

What the lane needs: headless one-shot, machine-readable result, auto-approve
edits, resume by id for fix rounds 1 to 3, and ideally schema enforcement on
the six-field report in `scripts/codex-report-schema.json`.

| CLI | Headless | JSON out | Schema | Resume by id | Exit codes | Free inference |
|---|---|---|---|---|---|---|
| Codex CLI | `exec` | `--json` | **`--output-schema`** | `exec resume <id>` | undocumented | plan-bound |
| Qwen Code | `-p` | `-o json` | **`--json-schema`** | `--resume <uuid>` | **0/53/55/130** | **none since 2026-04-15** |
| Antigravity | `-p` | `--output-format json` | **`--json-schema`** | `--conversation <id>` | 0/non-zero | free tier, quota unpublished |
| Gemini CLI | `-p` | `-o json` | no | `-r`, `--session-id` | 0/1/42/53 | **none since 2026-06-18** |
| opencode | `run` | `--format json` | no | `-s <id>`, `--fork` | undocumented | Zen free models |
| Goose | `run --no-session` | `--output-format json` | no | `--session-id` | non-zero | none (BYOK) |
| Crush | `run` | **none — prose** | no | `-s <id>` | 0/1 | none (BYOK) |
| Aider | `-m` | none | no | none | **always 0** | none (BYOK) |

Qwen Code's `--json-schema` is headless-only, validates under strict Ajv, and
in text mode emits exactly the JSON payload with no envelope. Its docs'
recommended recipe for a "trusted, isolated environment (ephemeral CI runner,
container)" is close to this lane's architecture.

## Findings that outlive the decision

1. **`scripts/detect-executors.sh`'s antigravity row is stale.** Its recorded
   reason — that the only agent mode opens a GUI editor session with no output
   file, no completion signal and no exit code — no longer holds. Antigravity
   CLI now has `agy -p`, `--output-format json|stream-json`,
   `--conversation <id>` and `--json-schema`. It still fails the criterion, but
   on unpublished quota, not on batch incapability. Registered as item 6.

2. **Schema enforcement is not unique to Codex.** Qwen Code and Antigravity CLI
   both enforce a JSON schema on the final response. If a second executor is
   ever built, the report contract need not degrade to prompt-and-parse — which
   was the assumption behind rejecting `runAppServerReview`.

3. **Gemini CLI's `--approval-mode` is silently overridden** to `default` when
   the folder is untrusted: "Approval mode overridden to 'default' because the
   current folder is not trusted." A worktree the lane just created is
   untrusted, so auto-approval would quietly not apply. `--skip-trust` fixes
   it. Measured. Any future Gemini-family wrapper needs this flag.

4. **Qwen Code reports success on provider failure.**
   [#11217](https://github.com/QwenLM/qwen-code/issues/11217) and
   [#8920](https://github.com/QwenLM/qwen-code/issues/8920), both open: with
   `-o json` or `stream-json` a provider error exits 0 with
   `subtype=success, is_error=false`. The lane survives this only because
   `reference/executor-lane.md` already makes the contract files and commits
   rather than the result object.

5. **Vendor READMEs lag reality by months.** Gemini CLI's README on `main` still
   advertises "60 requests/min and 1,000 requests/day with personal Google
   account" three months after that path stopped serving. Never evaluate a free
   tier from a README.

6. **Weight published hard numbers above generous-sounding wording.** iFlow's
   free tier was never labelled promotional — staff answered a direct question
   with "暂无收费计划，免费使用哈~" ("no charging plans for now, use it free") —
   and it read as more generous than OpenCode Zen's explicit "limited time".
   It proved strictly worse: the whole service was withdrawn with four weeks'
   notice. An unpublished quota presented as permanent is not generous, it is
   unmeasurable.

## If the lane is built anyway

Ranked. All carry the caveat that the lane's own economics are unfavourable.

1. **Qwen Code + local inference** (Ollama, vLLM or llama.cpp through its
   Custom Provider). The only genuinely zero-cost, quota-free, no-terms-risk
   path surveyed, and it keeps the best CLI contract. Paid for in hardware and
   a real capability drop. Nothing can be withdrawn by a vendor.
2. **Qwen Code + OpenRouter** with the $10 spent, scoped to score-2 tasks.
3. **Goose + OpenRouter**, if #11217 is judged disqualifying.

A **free-model review seat** remains the cheapest way to get value from any of
this. It needs no commit contract, no output schema and no session resume, and
it tolerates rate limits and model churn, because a failed run means no second
opinion rather than a corrupted worktree. OpenCode Zen fits it as installed.

## Sourcing caveat

During this survey a research subagent fabricated three plausible GitHub issue
citations. They were caught and excluded, and every claim above traces to a
vendor document or issue tracker fetched directly, or to a command run on this
host. Treat any uncited number in this area with suspicion.
