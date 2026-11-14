# API-billed auto-run decisions, cache keep-warm and agy Hydrogen

**Execution strategy:** sequential — inline execution
**Depth:** full — risk,new-subsystem

## Goal

Three changes to dforge, from one owner list (register
`docs/dforge/registers/2026-11-14-decisions-cache-and-credits.md`):

1. **Auto-run decisions on API budgets** (rows 1, 4, 5). In an auto run, a
   question with listed options goes first to OpenAI's Decisions API, and a
   ruling that needs a reasoning judge goes first to a judge billed to a
   developer API budget (the Anthropic key, the OpenAI key, AgentRouter). The
   subscription's `judge-opus` seat rules only when no budget can; the Fable
   batch, `judge-sonnet-high` rulings and the three rulings named under The
   ladder stay on the subscription. Row 4 is covered for the Claude and
   OpenAI credits; its $10 Google credit stays unspent by the owner's Judge
   budget answer.
2. **Cache keep-warm** (row 2). While the session waits on background work,
   the cockpit submits a one-line turn shortly before the prompt cache
   expires, so the next real turn does not re-write the whole context.
3. **agy Hydrogen** (row 3). Measure Gemini 4 Hydrogen against Gemini 4 Argon
   as an agy reviewer, and give Hydrogen Argon's roster slots only if it
   passes a rule fixed here in advance.

## Decisions

- **Flow.** Asked fast mode or the full flow; answer: "Full dforge flow
  (Recommended)".
- **Credit form.** Asked what form the free credits take; answer: "Developer
  API keys".
- **Credit use.** Asked what work the credits pay for (offered: quota
  overflow, extra reviewers, auto-run decisions, implementation tasks);
  answer: "Auto-run decisions". No reviewer, implementer or attended-session
  seat moves to an API budget.
- **Jev.** Asked what role Jev takes in the rulings; answer: "CAn retire on
  Jev, but use decision API from openAI API". Jev is dropped. The role
  question was not answered separately, so the recommended role offered in
  that question is taken: the Decisions API is the first rung and escalates
  when it is not confident.
- **Judge budget.** Asked which budgets pay for the reasoning judge before the
  subscription does (offered: AgentRouter, OpenAI key, Anthropic key, Google
  key); answer: "Anthropic key, OpenAI key, AgentRouter OpenAI model". The $10
  Google credit is not used.
- **Hydrogen.** Asked where Hydrogen goes in the agy roster; answer: "Measure
  first".
- **Budget order.** Asked at the spec review in which order the budgets are
  tried (offered: Anthropic, OpenAI, AgentRouter; AgentRouter, OpenAI,
  Anthropic); answer: "Anthropic, OpenAI, AgentRouter (Recommended)". The
  first judge is the model the subscription seat runs, and code reaches the
  third party only when both first-party budgets are closed.
- **Approach** (recorded here, not asked). Three were weighed:
  (a) *do-less*: keep the rulings on the subscription, tell the session in
  prose to hand off before a long wait, and swap the model name in the agy
  roster. It adds no code and fails rows 1, 2, 4 and 5.
  (b) *session-side prose*: the skills tell the session to call the Decisions
  API, set the keys and start the judge CLIs itself. It is small, but key
  handling, the spending caps and the confidence rule would live in prose the
  session may not follow and no test can reach, and a waiting session has no
  turn in which to keep its own cache warm.
  (c) *scripts and a cockpit timer* (chosen): three scripts own the calls, the
  keys and the caps, and the cockpit watchdog owns the keep-warm. Every rule
  is code a test reaches with stubs, as `run-agy-review.sh` is for agy.
- **Spec review (2026-11-14).** Live billed calls on the three keys (A20):
  "Right". Ten billed agy Gemini review runs (A26): "Right".
- **Default mode** (recorded here, not asked). `decisionApi` ships `off`;
  nothing calls the Decisions API until the owner sets it to `shadow` or `on`
  and sets `apiBudgetOpenai` above 0.
- **Wait per ruling** (recorded here, not asked). A ruling can wait up to 40
  minutes on the API judges before the subscription seat is tried. That wait
  is taken as the cost of spending the budgets first.
- **Judge transport** (recorded here, not asked). The judges run through the
  vendors' headless CLIs (`claude --bare -p`, `codex exec`), not raw HTTP: a
  ruling judge must read the plan, the spec and the code, and the CLIs bring
  read-only file tools.

Early CI: none

Finish: merge

Worktree: in-place

## Design

### What stays as it is

Outside an auto run nothing changes. Inside one, task reviews, plan reviews,
the final review, the spec review, the Fable batch and the second, independent
`judge-opus` dispatch that confirms a Header amendment all stay on the
subscription. The rule that an auto run never performs an irreversible,
destructive, security-sensitive or outside-workspace operation, whatever a
ruling says, stands unchanged.

### Keys

dforge reads three variables and nothing else:
`DFORGE_OPENAI_API_KEY`, `DFORGE_ANTHROPIC_API_KEY` and
`DFORGE_AGENTROUTER_API_KEY`. The vendors' own variable names are never read:
an exported `ANTHROPIC_API_KEY` would move the whole Claude Code session onto
API billing, and an exported `OPENAI_API_KEY` can do the same to Codex
reviews.

The keys are exported in the owner's shell profile, so the session and
everything it runs can read them; dforge does not change that. What its
scripts guarantee is narrower:

- A judge child starts with all three `DFORGE_*_API_KEY` variables and both
  vendor variables removed from its environment, then the one variable its
  provider needs set (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY` or the provider's
  `env_key`).
- Before a judge's reply is written to `--report`, it is searched for each of
  the three key values. A hit fails the run with `reason=key-in-reply` and
  the reply is discarded.
- No script prints, logs or writes a key value.

### Budgets and the spend file

A budget is `openai`, `anthropic` or `agentrouter`. Each has a cap setting in
US dollars, 0 by default: `apiBudgetOpenai`, `apiBudgetAnthropic`,
`apiBudgetAgentRouter` (0 to 1000, step 5, `zero: 'off'`, enforced by script).
The AgentRouter setting's description says that a cap above 0 sends ruling
prompts, and any file its judge reads, which can be any file this user can
read, to AgentRouter: setting it is the consent.

`scripts/api-spend` keeps `~/.dforge/api-spend.json`, one object per budget
with `spent_usd` and `calls`, written under a lock:

- `api-spend status` prints one line per budget:
  `api-budget <id> open=<true|false> spent=<usd> cap=<usd> reason=<token>`.
- `api-spend add <id> <usd>` adds to the amount. Only the two scripts below
  call it.

A budget is open when its cap is above 0, its key variable is set, and its
recorded spend is below 95% of the cap. Otherwise it is closed with
`reason=off`, `no-key` or `spent`. The file counts only what dforge spent, so
the vendor's console stays the authority (Known limits).

`reference/api-prices.json` holds per-million-token prices per model, with the
vendor page and the date each was read. The plan fills it from the vendors'
pricing pages. The `openai` and `agentrouter` budgets are charged from token
counts, so a model of theirs with no row closes its budget with
`reason=no-price`. The `anthropic` budget is charged from the cost its CLI
reports and needs no row.

### The Decisions API rung: `scripts/decide`

OpenAI's Decisions API (`POST https://api.openai.com/v1/decisions`, model
`gpt-6-luna`, $0.10 per million input tokens, no output charge;
https://developers.openai.com/api/docs/guides/decisions, read 2026-11-14)
answers typed questions over supplied text. It cannot read the repository.

    scripts/decide ask --id <id> --question "<q>" --options "<recommended | other ...>" [--evidence <file>]...
    scripts/decide record --id <id> --ruling "<choice>"
    scripts/decide report

`ask` sends one request. Its `input` is the question and the evidence files'
text. Its `questions` are:

- `ruling`, a choice over the options in the order given, followed by a
  last option `other` ("none of the listed options fits"), as OpenAI's guide
  advises;
- `ruling_reversed`, the same choice with the listed options reversed and
  `other` still last, a precaution of this design against a bias toward
  the first option;
- `needs_more`, a predicate: choosing correctly needs information that is not
  in the evidence, such as reading source files or running code;
- `guarded`, a predicate: an option involves an irreversible or destructive
  operation, a security-sensitive action, or a change outside the working
  directory.

It prints `ruling: <choice> — Decisions API (confidence <c>)`, `<c>` the
lower of the two confidences, and exits 0 only
when all of these hold: the mode is `on`; both choices name the same listed
option (`other` from either is `reason=needs-more`); both `confidence` values
are at or above the `decisionConfidence` setting (50 to 99 percent, default
85); `needs_more` is at most 0.15; `guarded` is at most 0.10; no answer is a
refusal. Otherwise it prints
`no ruling reason=<token>` and exits 3, with `<token>` one of `off`, `shadow`,
`no-run`, `closed`, `disagree`, `low-confidence`, `needs-more`, `guarded`,
`refusal`, `evidence`, `error`. Exit 2 is a usage error.

- **Mode.** The `decisionApi` setting is `off` (default), `shadow` or `on`.
  `off` makes no request. `shadow` makes the request and logs it but never
  rules, so thresholds can be judged on real questions before anything acts
  on them. OpenAI does not describe the probabilities as calibrated and says
  to set thresholds from labelled examples; `shadow` is how those are
  collected.
- **Auto runs only.** With no run bound to the session
  (`scripts/auto-run status` not 0) it exits 3 with `reason=no-run` and makes
  no request.
- **Budget.** It needs the `openai` budget open (`reason=closed` otherwise)
  and adds each request's cost to it.
- **Evidence.** An evidence file must lie under the resolved dforge documents
  root or state root (`scripts/dforge-path docs`, `state`; the state root is
  in the checkout and ignored by git, and in darkmem mode the documents root
  is in the mirror, outside the checkout), or else inside the working
  tree and not ignored by git. Anything else, or more than 400,000 bytes in
  total, is refused with `reason=evidence` before any request: ignored files
  are where secrets live, and OpenAI states no input limit to lean on.
- **Log.** Every `ask` in `shadow` or `on` mode appends one JSON line to
  `<state>/decisions.jsonl`, whether or not a request was made: the id, the
  options, the mode, the outcome token and, when the API answered, both
  choices and confidences and both predicates.
- **Record and report.** `record --ruling` takes one of the item's listed
  options, or `other` when the judge chose none of them; any other text is a
  usage error. `report` prints, per confidence band, how often the API's
  choice matched the judge's, and ends with `promote: yes` when at least 20
  recorded items sit at or above the confidence setting and at least 95% of
  them match, `promote: no (<n> recorded, <p>% match)` otherwise. The line
  is advice: only the owner changes the mode.
- **Failure.** A network error, a non-200 answer or 30 seconds without one is
  `reason=error`. Nothing is retried.

`DFORGE_DECISIONS_URL` points the tests at a local stub. Tests shorten the
waits and swap the roster through `DFORGE_DECISIONS_TIMEOUT`,
`API_JUDGE_BEAT`, `API_JUDGE_CHAIN` and `API_JUDGE_LADDER`, as
`AGY_REVIEW_LADDER` and `AGY_REVIEW_GRACE` do for agy.

### The API-billed judge: `scripts/run-api-judge`

    scripts/run-api-judge --prompt <file> --report <file> --cwd <worktree> [--add-dir <dir>]... [--dry-run]

It runs a ruling on the first open budget that produces a report. The roster
is a new `api-judge` block in `reference/ladder.md`, one row per budget in the
order tried, `budget model effort seconds`:

    anthropic claude-opus-5-5 medium 1800
    openai gpt-6-astra xhigh 1800
    agentrouter gpt-6-astra xhigh 1800

- The whole chain has 2400 seconds. A row gets its own seconds or what is
  left of the chain, whichever is less. A row that times out ends the chain
  with exit 3: a ruling too large for one judge goes to the subscription
  seat, not to a second paid attempt. So a ruling waits at most 40 minutes
  before the subscription seat is tried (Decisions, Wait per ruling).
- When a row starts, the script prints
  `api-judge <budget>:<model>/<effort> started`, and while the row runs one
  `api-judge <budget> running <seconds>s` line every 5 minutes. The auto
  run's reconcile prompt stops a launch whose output has been idle 30
  minutes (`scripts/lib/in-flight.sh`); these lines keep a live judge from
  looking idle.
- `--add-dir` names each directory outside `--cwd` that the prompt points at
  (the workspace holding the items file, ledger and amendments, and the
  documents root). The Anthropic run receives them as its own `--add-dir`
  arguments; the read-only Codex sandbox reads the whole disk.
- `agentrouter` and `openai` run `codex exec` in a read-only sandbox with a
  provider given by `-c` overrides (base URL `https://agentrouter.org/v1` or
  `https://api.openai.com/v1`, the key through the provider's `env_key`), in
  a session directory of their own so the Codex subscription login is not
  touched.
- `anthropic` runs `claude --bare -p` with only the Read, Grep and Glob tools
  and `ANTHROPIC_API_KEY` set for that process. Bare mode reads no OAuth
  login.
- The prompt is the ruling prompt the subscription seat gets, plus one
  paragraph: the judge cannot write files and replies with the whole report.
  The script writes that reply to `--report` when it opens with `## Verdict`.
- Before and after each run the script snapshots the worktree
  (`scripts/lib/worktree-snapshot.sh`). A run during which a tracked or
  untracked file, the index or HEAD changed is `FAILED reason=wrote`, its
  answer is discarded, and the chain ends with exit 3: no further budget is
  tried, since whatever changed the worktree would void the next run too.
- Each budget tried prints one line:
  `api-judge <budget>:<model>/<effort> status=<OK|FAILED|TIMEOUT|SKIPPED> exit=<n> out=<path|-> spent=<usd> reason=<token>`.
  The same line is appended to `<state>/api-judge.log`.
- Cost goes to `api-spend add`: the Anthropic run's from the CLI's reported
  cost, the others' from the last token total in the CLI's event stream
  (`codex exec --json`, kept in a file as it arrives) and the price table. A
  failed or timed-out run is charged the same way. A run that reported no
  cost or tokens at all is charged a flat 1.00 USD, so repeated timeouts
  cannot spend unseen.
- Exit 0: a report was written. Exit 3: no budget produced one, or no run is
  bound to the session (`reason=no-run`); no report file exists. Exit 2:
  usage.
- Run it as a background Bash call with `timeout` 2520000 ms (the chain's
  2400 seconds plus 120). Do not pipe or redirect its output: the progress
  lines count only when they reach the launch's output file.

### The ladder in an auto run

`reference/auto-run.md` §Rulings and
`skills/executing-plans/references/ruling-seat.md` change as follows.
`skills/writing-plans/references/auto-run-plan.md` follows: its sentence
sending a planning choice to `dforge:judge-opus` first becomes "An approach
or planning choice you would ask about goes up the ladder in auto-run.md
§Rulings, from its first rung." Every other reader keeps its text.

Both rungs apply only on Claude Code, where auto runs exist.

1. **A choice item** is a spec or planning choice before execution: a
   question with its options, the recommended one first. Run
   `scripts/decide ask` first, with the spec, the plan when one exists and
   the files the question names as evidence. On exit 0 the printed ruling
   stands; record it with
   `scripts/auto-run ruling add "Decisions API: <item> — <ruling>"`. On exit 3
   go on to rung 2. An acceptance statement rated below `high` is not a
   choice item and goes up the ladder as today. An item a judge has already
   declined to rule never returns to the Decisions API.
2. **A ruling the route gives to `dforge:judge-opus`** (before execution, or
   at the execution ruling seat): run `scripts/run-api-judge` first with the
   same prompt and report file. On exit 0 read the report's `## Verdict` as
   the seat's. On exit 3 dispatch the subscription seat as today. After
   starting `run-api-judge`, end the turn and wait for its notification;
   until it ends, change nothing under `--cwd` that git does not ignore, and
   run no git command there that changes its index or HEAD. Three
   rulings skip this rung and go to the subscription seat directly: a
   `preflight` ruling, which reads the whole plan against the spec and has
   outrun 1800 seconds on Astra before (`reference/ladder.md`); the fresh
   dispatch after `plan-amend` rejects an AMEND; and the independent
   confirmation of a Header amendment. A ruling the route gives to
   `dforge:judge-sonnet-high` is dispatched as today.
3. In `shadow` mode, after rung 2 rules a choice item, run
   `scripts/decide record`.
4. The pending list and the Fable batch follow unchanged.

Finishing's final message adds the lines of `scripts/api-spend status` and
names the settings and key variables that are still off.

### Cache keep-warm

Main sessions write the one-hour cache (eight transcripts of 2026-11-14: only
`ephemeral_1h_input_tokens` writes). A turn after the cache expires re-writes
the whole context at twice the input price; a turn that reads it costs a
tenth. During an auto run the cockpit's reconcile prompt already gives the
session a turn every 20 minutes of background work
(`hooks/cockpit/register.tsx`, `reconcileBackground`). Outside one nothing
does, and the heavy review panel (5590 s), the suite run (3600 s) and the CI
watch (5400 s) can each outlast the hour.

A new setting `keepWarm` (minutes, 0 to 59, default 50, `zero: 'off'`, group
Context) and one rule in the cockpit watchdog:

- When no auto run is bound to the session, no turn is live or waiting on
  the person, the main loop has an unfinished agent or a background shell
  that is not a service command, and `keepWarm` minutes have passed since the
  last main turn ended, the cockpit submits: "Keep-warm: background work is
  still running and the prompt cache is about to expire. Reply with the
  single line `Still waiting.` and end the turn. Start nothing and call no
  tool."
- At most six in a row. A turn from any other origin (the person, a task
  notification, another cockpit prompt) resets the count.
- A keep-warm turn is marked in the cockpit's state. It neither drops nor
  replaces a Done notification the cockpit is holding for the background
  work, and it sends no Done notification of its own.
- A session on the five-minute cache sets `keepWarm` to 4.

While an auto run is bound, no keep-warm prompt is sent: the reconcile turn
every 20 minutes already reads the one-hour cache, and a keep-warm turn there
would move the clock the reconcile's hang detection counts from.

Whether `$.prompt.submit` disturbs a message the person has half typed is not
known. The plan's keep-warm task checks it under `claude plugin test` before
anything else. If a draft is disturbed, a keep-warm prompt is sent only while
the engine reports an empty composer; if the engine cannot report that, the
setting ships with default 0.

`reference/session-budget.md` §Idle describes the rule.

### agy Hydrogen: measure, then place

agy 1.5.7 lists `gemini-4-hydrogen` at low, medium, high and xhigh; no public
ranking against Argon was found (2026-11-14). The measurement runs once,
during the plan, in a scratch clone of this repository, never in the real
checkout:

- Three merged feature branches from this repository's history, each reviewed
  with `run-agy-review.sh --kind final --base <sha>` under three fixture
  ladders (`AGY_REVIEW_LADDER`): `gemini-4-argon high`,
  `gemini-4-hydrogen high`, `gemini-4-hydrogen xhigh`. Nine runs, plus one
  `--kind task` run on Hydrogen, made after the nine at the effort the rule
  selects, to prove it accepts the review schema.
- A `dforge:judge-opus` dispatch weighs each list blind to the model that
  wrote it and marks every finding confirmed or not.
- Only Gemini quota is spent. No run names a Claude model.

**The rule.** Take Hydrogen at the effort with more confirmed findings in
total, `high` on a tie. Hydrogen replaces Argon in both of its slots, the
light reviewer and the heavy fallback, when at that effort it returned a usable
list on all three branches and on the task run, its confirmed findings in
total are at least Argon's, the share of its findings the judge did not
confirm is no more than ten percentage points above Argon's, and its slowest
run finished inside the row's 2400 seconds. Otherwise Argon stays and
Hydrogen joins no roster. The note records both models' confirmed counts and
unconfirmed shares.

The result goes to `docs/dforge/notes/2026-11-14-agy-hydrogen-review.md`,
ending in one line: `Verdict: <model> <effort>`. The `agy-judge` block's last
row, `reference/external-review.md`, the README and the tests that name the
agy Gemini reviewer follow that line. The first row
(`claude-opus-5-5 high 5400`) is not touched: measuring against it would spend
the scarce Claude quota in agy. `reference/agy-policy.json` sets `calibrated`
to the agy version the runs used. When the verdict is Hydrogen it sets
`min_version` to that version too: the gate (`scripts/agy-locate`) reads
`min_version`, the light tier runs the last row with no fallback, and an agy
that passes the gate without listing Hydrogen would fail every light review.

### Files

New: `scripts/decide`, `scripts/run-api-judge`, `scripts/api-spend`, a shared
`scripts/lib/api-budget.sh`, `scripts/lib/decisions.mjs`,
`reference/api-prices.json`, their tests and stubs, and the measurement note.
Changed: `config/schema.mjs`, `reference/ladder.md`, `reference/auto-run.md`,
`skills/executing-plans/references/ruling-seat.md`,
`skills/writing-plans/references/auto-run-plan.md`,
`skills/finishing-a-development-branch` (the spend lines),
`hooks/cockpit/register.tsx` and its test, `reference/session-budget.md`,
`reference/external-review.md`, `reference/agy-policy.json`,
`plugins/dforge/README.md`, `SECURITY.md`, `scripts/test-shards.mjs`, the
tests that pin the agy roster, and the plugin version (next minor).

### CI

`.github/workflows/validate.yml` runs on `ubuntu-latest` and on
`windows-latest` in 14 shards. This host is GNU Linux (`cp --version`: GNU
coreutils 9.7), so `uutils (ubuntu-latest)` and `Windows Git Bash` are
uncovered. The new scripts follow the pitfalls in `reference/ci-parity.md`.

## Acceptance

A1. [test, high] With `decisionApi=on`, a run bound, the `openai` budget open and a stub endpoint answering both orderings with the same listed option at confidence at or above the setting and both predicates below their limits, `scripts/decide ask` prints `ruling: <that option> — Decisions API (confidence <c>)`, `<c>` the lower of the two confidences, and exits 0.
A2. [test, neg, high] `scripts/decide ask` prints `no ruling reason=<token>`, exits 3 and prints no `ruling:` line when the orderings disagree, either answers `other`, a confidence is below the setting, `needs_more` is above 0.15, `guarded` is above 0.10, an answer is a refusal, or the request fails or passes 30 seconds; each case prints the token the design names for it.
A3. [test, neg, high] With `decisionApi=off`, with no run bound to the session, or with the `openai` budget closed, `scripts/decide ask` sends no request and exits 3; with `decisionApi=shadow` it sends the request, prints `no ruling reason=shadow` and exits 3.
A4. [test, neg, high] `scripts/decide ask` sends no request and exits 3 with `reason=evidence` when an evidence file lies outside the working tree and both dforge roots, lies inside the working tree but is ignored by git, or the evidence exceeds 400,000 bytes.
A5. [test, high] `scripts/decide ask` accepts as evidence a spec that lies under the dforge documents root outside the working tree, and a file under the state root that git ignores.
A6. [test, high] Every `ask` in `shadow` or `on` mode appends one JSON line to `<state>/decisions.jsonl` holding the id, the options, the mode and the outcome token, with both choices, both confidences and both predicates when the endpoint answered; an `ask` refused before any request is logged too.
A7. [test, high] `decide record` appends the judge's choice for an id when it is a listed option or `other` and exits 2 on any other text; `decide report` prints match counts per confidence band and ends with `promote: yes` only when at least 20 recorded items sit at or above the confidence setting and at least 95% of them match.
A8. [test, neg, high] With a sentinel value in each `DFORGE_*_API_KEY` variable, no run of `decide`, `run-api-judge` or `api-spend` leaves a sentinel in stdout, stderr, `decisions.jsonl`, `api-judge.log`, `api-spend.json` or the report file; a judge reply containing a sentinel is reported `FAILED` with `reason=key-in-reply` and is not written to `--report`.
A9. [test, neg, high] A judge child's environment holds none of the three `DFORGE_*_API_KEY` variables and no vendor key variable other than the one its provider needs, and a Codex child's `CODEX_HOME` is not the user's.
A10. [test, neg, high] With `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` set and the three `DFORGE_*_API_KEY` variables unset, each cap above 0, every budget is closed with `reason=no-key` and no request or CLI run starts.
A11. [test, high] `scripts/run-api-judge` tries the open budgets in the `api-judge` block's order; the first whose CLI returns text opening with `## Verdict` has that text written to `--report`, the script exits 0, and one `api-judge` status line is printed and logged per budget tried.
A12. [test, high] `scripts/run-api-judge` prints a `started` line when a row begins and a `running` line at least every 5 minutes while it runs.
A13. [test, high] A budget whose run fails or returns text not opening with `## Verdict` is reported `FAILED` and the next open budget is tried; a run that passes its seconds, or the 2400 seconds of the chain, is reported `TIMEOUT` and no further budget is tried, and neither is one after a `FAILED reason=wrote`; when no report was produced the script exits 3 and no report file exists.
A14. [test, neg, high] A budget with cap 0, no key, recorded spend at or above 95% of its cap, or (for `openai` and `agentrouter`) no price row for its model starts no CLI and is reported `SKIPPED` with its reason.
A15. [test, neg, high] A judge run during which a tracked or untracked file of the worktree, its index or HEAD changed is reported `FAILED reason=wrote`, its text is not written to `--report`, and no further budget is tried.
A16. [test, high] After a call, `api-spend status` shows the budget's `spent` grown by that call's cost: the Anthropic CLI's reported cost, or for the others the last token total of the run priced from `reference/api-prices.json`, for a timed-out run as well; a run that reported neither cost nor tokens adds 1.00; a Decisions request is charged to `openai`.
A17. [test, neg, high] With no auto run bound to the session, `scripts/run-api-judge` exits 3 with `reason=no-run` and starts no CLI.
A18. [test, high] Each `--add-dir` directory given to `scripts/run-api-judge` reaches the Anthropic CLI as an `--add-dir` argument.
A19. [demo, high] In an auto run with a budget open, a pre-execution choice is put to `scripts/decide ask` first, and a ruling routed to `dforge:judge-opus` other than a `preflight`, a rejected AMEND's retry or a Header confirmation is put to `scripts/run-api-judge` first; the subscription seat is dispatched only after exit 3.
A20. [demo, confirmed] With the three key variables set to real keys, one live ruling per budget returns a report opening with `## Verdict`, and one live `decide ask` returns an answer; the user's Codex auth file is byte-identical before and after, and the session's Claude login is unchanged.
A21. [test, high] With `keepWarm=50`, no auto run bound, no live turn, a main-loop background shell running and 50 minutes passed since the last main turn ended, the cockpit submits the keep-warm prompt once, and once more per further 50 minutes.
A22. [test, neg, high] The cockpit submits no keep-warm prompt when `keepWarm` is 0, an auto run is bound to the session, a turn is live or waiting on the person, only service commands or no background work is running, or six keep-warm prompts have been sent since the last turn of any other origin.
A23. [test, high] A turn of any other origin resets the keep-warm count, so a later wait can send six again.
A24. [test, neg, high] A keep-warm turn leaves a held Done notification in place, does not become its text, and sends no Done notification of its own.
A25. [test, high] `decisionApi`, `decisionConfidence`, `apiBudgetOpenai`, `apiBudgetAnthropic`, `apiBudgetAgentRouter` and `keepWarm` are settings in `config/schema.mjs` with the defaults `off`, 85, 0, 0, 0 and 50 (0 when the draft check of Cache keep-warm found a disturbed draft and no composer state to read) and the ranges the design gives.
A26. [demo, confirmed] The measurement note records nine final-kind runs and one task-kind run on real agy, each list weighed by a judge, both models' confirmed counts and unconfirmed shares, and ends with a `Verdict:` line the rule produces.
A27. [test, high] The last row of the `agy-judge` block names the model and effort of the note's `Verdict:` line; `reference/agy-policy.json` `calibrated` equals the agy version the note records, and `min_version` equals it too when the verdict names Hydrogen.
A28. [test, neg, high] The first row of the `agy-judge` block is still `claude-opus-5-5 high 5400`.
A29. [demo, high] The keep-warm task's report states what `$.prompt.submit` did to a half-typed composer under `claude plugin test`, and which of the three outcomes the design names was shipped.
A30. [demo, high] An auto run's final message carries one `api-budget` line per budget.
A31. [test, high] `skills/writing-plans/references/auto-run-plan.md` does not name `dforge:judge-opus` and sends an approach or planning choice to `reference/auto-run.md` §Rulings; in that section `scripts/decide ask` and `scripts/run-api-judge` both appear above the pending-list rung.

## Riskiest assumption

That a headless vendor CLI, given a key in its own process environment, runs a
read-only ruling judge on that key without touching the subscription login,
and reports what the run cost. Evidence so far is the CLIs' own help, read
2026-11-14: `claude --help` says `--bare` uses "strictly ANTHROPIC_API_KEY or
apiKeyHelper via --settings (OAuth and keychain never read)"; `codex exec
--help` lists `-c <key=value>` overrides and a read-only sandbox; AgentRouter's
Codex page (https://agentrouter.org/docs/codex.html) configures a
`model_providers` entry with an `env_key`. No key is set in this shell, so
nothing was run against a vendor: unverified — the plan's first task verifies
it, with `--dry-run` and stubs, and live when A20 is confirmed. If the first
task disproves it for a CLI, that budget's row leaves the `api-judge` block
and its register row is deferred; no raw-HTTP judge is built in this plan.

## Known limits

- The Decisions API's confidence is not documented as calibrated. The default
  mode is `off`, and `shadow` exists to gather evidence before `on`.
- The spend file counts only dforge's calls. Other use of the same keys is
  not seen, AgentRouter may price a call differently from OpenAI's list, and
  a cap is an estimate: switch off auto-recharge in each vendor console.
- AgentRouter is a third party. Its terms (read 2026-11-14 by the spec
  review, https://agentrouter.org/docs/terms.html) do not ban automation;
  they list prolonged uninterrupted automated polling and high-volume
  automated requests not tied to real development as improper, and say
  nothing on whether prompts are kept or used for training. The ruling prompt and every file its judge reads pass through it. Its
  budget is closed until its cap and key are set.
- A Codex judge reads any file this user can read, the shell profile that
  holds all three keys included; the Anthropic judge reads the worktree and
  its `--add-dir` directories, ignored files included. The scrubbed
  environment and the reply scan stop an accidental leak, not a judge
  steered to look. Only `decide` filters its evidence.
- Text in the evidence can try to steer the classifier. Agreement across both
  option orders, the two predicates and the never-performed rule bound what a
  steered answer can do.
- Keep-warm is sized for the one-hour cache. On the five-minute cache, six
  prompts at `keepWarm=4` hold the cache for about 29 minutes; a longer wait
  pays for the six reads and the re-write both.
- A wait inside a live turn (a foreground subagent or command) cannot be
  kept warm: no prompt can be submitted into a live turn.
- Under `autoRun=on` the spec's choices are asked at the spec review before
  the run starts (`reference/auto-run.md` §The spec), so only planning
  choices reach the Decisions API; 20 recorded items can take several runs.
- The Hydrogen measurement is three branches. It can show Hydrogen is not
  worse than Argon on them; it cannot rank the two in general.

## Critic findings

The architecture critic (2026-11-14) reported 0 Blocker, 4 High, 10 Medium and
3 Nit. Every High finding is fixed in the design above.

- [High] A silent background judge run can be stopped by the reconcile
  prompt. Fixed: `run-api-judge` prints a start line and a line every 5
  minutes, and the chain is capped at 2400 seconds.
- [High] Exported keys reach every process, the Codex judge's shell included.
  Fixed: the Keys section states what is and is not guaranteed, judge
  children start with a scrubbed environment, and a reply holding a key value
  is discarded (A8, A9).
- [High] The evidence rule refused the spec and plan outside the working
  tree. Fixed: the dforge documents and state roots are allowed, and the spec
  and plan are required evidence (A4, A5).
- [High] Hydrogen replaced Argon without raising agy's `min_version`. Fixed:
  a Hydrogen verdict sets `min_version` (A27).
- [Medium] 1800 seconds at xhigh conflicts with the ladder's timing record.
  Fixed: `preflight` rulings go to the subscription seat directly.
- [Medium] A timed-out run was charged nothing. Fixed: the last token total
  seen is charged, 1.00 USD when none (A16).
- [Medium] The Claude judge may not read files outside `--cwd`. Fixed:
  `--add-dir` (A18).
- [Medium] Acceptance statements were called choice items without options.
  Fixed: they are not choice items.
- [Medium] No rule for moving from `shadow` to `on`. Fixed: the `promote:`
  line and the option-only `record` (A7).
- [Medium] Keep-warm turns interfere with the held Done and the reconcile
  timer. Fixed: no keep-warm while an auto run is bound, and a keep-warm turn
  leaves the held Done alone (A22, A24).
- [Medium] Keep-warm prompts can arrive while the person is typing. Answered:
  the engine's behaviour is unknown, so the plan checks it first and the
  design names both outcomes.
- [Medium] The Hydrogen rule ignored false findings. Fixed: the unconfirmed
  share is bounded and recorded.
- [Medium] Retries and the Codex host were not covered. Fixed: a rejected
  AMEND's retry goes to the subscription seat, and both rungs are Claude Code
  only.
- [Medium] No record explains why a ruling skipped the Decisions API. Fixed
  in part: every `ask` in `shadow` or `on` mode is logged with its outcome
  (A6). No ruling-list line is written for a skipped ask, and the cockpit
  shows no keep-warm count.
- [Nit] The price-row rule contradicted how the Anthropic run is charged.
  Fixed.
- [Nit] The choice question had no fallback option. Fixed: `other`.
- [Nit] Setting the AgentRouter cap is the consent to send code to a third
  party. Fixed: the setting's description says so.

## Review rulings

Fable, round 1 (2026-11-14): 22 rulings, 1 undecided, 2 High findings fixed.

- Jev role — stands: first rung, escalating; a Known limit on how few choice items a run meets was added.
- $10 agy credit — stands unused; Goal item 1 says so.
- Approach (c) — stands.
- Judge transport — stands.
- `decisionApi` default `off`, shadow before `on` — stands; recorded as a Decisions bullet, and the final message names what is still off.
- The 40-minute wait per ruling — stands; recorded as a Decisions bullet.
- Fable batch and `judge-sonnet-high` rulings stay on the subscription — stands; Goal item 1 reworded.
- `keepWarm` default 50 and no keep-warm in an auto run — stands; a Known limit on waits inside a live turn was added.
- Critic High 1 (reconcile stop) — fix holds; the output must not be piped or redirected.
- Critic High 2 (keys) — fix holds; Known limits and the AgentRouter consent now say what a judge can read.
- Critic High 3 (evidence roots) — fix holds; the state root's location was corrected.
- Critic High 4 (`min_version`) — fix holds.
- AgentRouter terms — readable; the Known limit quotes what they say.
- Five-minute cache — the figure now reflects the cap of six.
- A25 against the draft check — reworded, and A29 added.
- A10 — made checkable with each cap above 0.
- A1 — the printed confidence is the lower of the two; the first-option precaution is the design's own.
- A2, A12, A13 — test seams named so the waits can be shortened.
- Riskiest assumption — stands; A9 and A20 extended, and the fallback when a CLI disproves it is stated.
- Finishing's spend lines — A30 added.
- Hydrogen task-kind run — made at the effort the rule selects.
- A20 and A26 questions — stand as owner questions.
- [High] `auto-run-plan.md` sent planning choices to `judge-opus` first — fixed: the file follows the ladder, and A31 added.
- [High] nothing held the worktree still during a background judge run — fixed: rung 2 says so, and a `wrote` failure ends the chain (A13, A15).
- Undecided, for the owner: the budget order (settled at the spec review; see Decisions).

Fable, round 2 (2026-11-14): both High fixes hold, 0 open.

- `auto-run-plan.md` fix — holds; A31 reworded so a test can decide it.
- Worktree held still — holds; rung 2's wording tightened to cover deletions, staging and HEAD.
