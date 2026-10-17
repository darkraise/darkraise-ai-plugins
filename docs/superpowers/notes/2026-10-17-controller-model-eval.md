# Controller model for subagent-mode plans — evaluation

Written 2026-10-17. Status: research only; no paid run made, nothing changed.
Answers register `2026-10-17-run-order-finish-controller.md` item 3.

## Question

Should the subagent-mode controller run `claude --model opus --effort low|medium`
instead of the current `claude --model sonnet --effort high`
(`plugins/dforge/skills/writing-plans/SKILL.md`, "Choosing the Execution line")?
The owner reports that Claude Code cloud uses Opus at low/medium as its
controller; this is unverified and taken here as their observation.

## Answer

Do not switch yet. Run the small pilot below, with Opus 5.5 `low` as the only Opus
arm. Based on the paired data, Opus `low` should raise the controller's cost by
about 40% (about +$4 per plan, +10% of plan spend), and Opus `medium` by about
90% (about +$9, +22%). The controller failures on record are about keeping
track of background work, not about judgment, and the harness already patches
most of them. Nothing on record shows that Opus fixes them.

## Pricing (live, fetched 2026-10-17)

| Model | Input | 5m write | 1h write | Cache read | Output |
|---|---|---|---|---|---|
| Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
| Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 | $10 |

Opus 5.5 costs exactly 2x Sonnet 5.5 on every meter, so an Opus controller
breaks even only if it uses half the tokens. Source:
<https://platform.claude.com/docs/en/about-claude/pricing> (footnote 2: cache hits
on both models are 0.05x base input). The `claude-api` skill's cached table
(2026-10-06) still lists Sonnet 5.5 cache reads at $0.20; the live page wins.

Effort guidance:

- <https://platform.claude.com/docs/en/build-with-claude/effort>: Opus 5.5 defaults
  to `medium` and you should "run an effort sweep on your own evals". The level
  table lists `low` for "simpler tasks … such as subagents". For Sonnet 5.5: "for
  agentic coding and multistep tool use, start with `medium` for well-specified
  tasks and move to `high` for harder or longer ones". Lower effort means
  "fewer and terser tool calls".
- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
  (§Calibrate effort; §Unattended agentic runs): at a given level Opus 5.5
  "tends to think more per turn" than Opus 5. On long multi-part tasks some
  progress updates "end the turn with text rather than a tool call". That is the
  early-stop risk dforge already met in implementers (commit `7e274ec`).

## Evidence

### 1. Measured controller usage

Source: Claude Code transcripts in `~/.claude/projects/*/`, main session only;
subagent transcripts (`<session>/subagents/`) are counted separately. Requests
are deduplicated by message id and priced at the live rates above. Costs are
API-equivalent; the owner may pay by subscription.

- 53 subagent-mode controller sessions (any session that invoked
  `subagent-driven-development`), 2026-09-19 to 2026-10-17, across six
  repositories. Every one ran at `high` effort: 43 on Sonnet 5.5, 7 on
  Sonnet 5, and 3 on Opus 5.5. None ran Opus at `low` or `medium`, so those
  settings have no direct data.
- Baseline: 15 plans recorded complete (`completed.md` or a
  `docs(plans): complete` commit) whose controller sessions all ran on Sonnet 5.5
  high. They cover 29 sessions in darkcloud, darkpanel, darkraise-web-template
  and this repository.

| Per completed plan (15 plans) | Median | Mean |
|---|---|---|
| Controller API calls | 307 | 284 |
| Controller output tokens | 202k | 195k |
| Controller cache-read tokens | 66.1M | 61.5M |
| Controller cache-write tokens | 539k | 574k |
| Controller cost | $11.02 | $10.39 |
| Subagent cost (Claude seats only) | $22.17 | $31.52 |

- The controller is 24.8% of Claude-side plan spend. Codex executor and reviewer
  work is billed elsewhere and is excluded.
- Controller cost by meter: cache reads 59%, output 19%, cache writes and
  input 22%. The average request re-reads about 217k tokens of context.
- Per subagent dispatch: $0.21 and 5.8 controller calls.
- The 3 Opus 5.5 high controller sessions (darkcloud `6b1e5fc5`, ghr
  `dc2d4acb`, `e1437eeb`) carried 3 to 7 owner messages each and are not
  comparable. Their output per call was 692 to 1,473 tokens, against 688 for
  Sonnet.

### 2. Paired Opus-versus-Sonnet data on the same cases

Source: `evals/tiers/results/results.tsv`, 2026-10-02.

| Comparison, same cases | Cost ratio | Turns |
|---|---|---|
| Row 5 implementers: Opus low vs Sonnet high (10 cases, all 9/10 pass) | 1.41x | 7.2 vs 8.9 |
| Row 5 implementers: Opus medium vs Sonnet high | 1.90x | 10.6 vs 8.9 |
| Rows 3-4: Sonnet medium vs Sonnet high (equal pass) | 0.79-0.87x | 6.4 vs 8.6 |
| Code review: judge-opus@medium vs judge-sonnet-high | 1.86x | 18.5 vs 17.3 |

### 3. Recorded controller mistakes

Ledgers carry none. A keyword scan of 90 SDD ledgers found no controller entry
for a wrong dispatch, a skipped ledger line or a controller-caused fix round.
The controller writes its own ledger, so this is weak evidence. The transcripts
do show slips, all about tracking background work and waiting:

- darkcloud `dc97aea4`, 2026-09-28, Sonnet 5 high, dr-superpowers 1.22.1: the
  controller busy-waited with 456 calls to `sleep 1` ("No-op while awaiting
  notifications") and 293 `ListAgents` calls. That made 1,240 API calls and 707M
  cache-read tokens, about $84 of controller spend against $45 for all
  subagents. The skill now forbids it: "never poll a wait interface with short
  timeouts" (`subagent-driven-development/SKILL.md`, waiting rule).
- darkraise-web-template `2d3533a7`, 2026-10-14, Sonnet 5.5: the owner asked
  "why running 7 monitors?" The controller replied: "Because I stacked them. …
  That was sloppy, and one is enough."
- ghr `6871f185`, 2026-10-10, Sonnet 5.5: the controller reported "Nothing of
  mine is still running". The owner answered: "check status, I see that there
  are still agent and shell running".
- The owner sent "check status" nudges in 3 more sessions (`0a13d100`,
  `0c92a556`, `9fa73269`).
- Harness fixes already target this class of slip: `39cc554` ("never hand off or
  finish over work still in flight"), `edbeaab` (stopped work no longer counts
  as running), and the bounded-wait rule.

Nothing on record shows a judgment error by the controller; the ruling seat
holds those calls.

## Cost per completed plan

Inference. The ratios come from the paired runs in section 2, applied to the
measured Sonnet baseline. Controller work is lighter than implementation, so the
real ratios could be lower or higher.

| Controller | Ratio vs current | Controller, median plan | Plan total, mean plan | Change |
|---|---|---|---|---|
| Sonnet 5.5 high (measured) | 1.00x | $11.0 | $41.9 | — |
| Opus 5.5 low | ~1.4x (1.2-1.6) | ~$15.5 | ~$46.2 | +$4.3 (+10%) |
| Opus 5.5 medium | ~1.9x (1.8-2.1) | ~$20.9 | ~$51.3 | +$9.4 (+22%) |
| Opus 5.5, same token profile (ceiling reference) | 2.0x | $22.0 | $52.3 | +$10.4 (+25%) |
| Sonnet 5.5 medium (extra arm) | ~0.8x (0.75-0.9) | ~$9.1 | ~$40.1 | -$1.8 (-4%) |

For Opus `low` to beat the current cost, it would need about half the
controller's calls times context. The paired runs show only 19% fewer turns.

## Recommendation: a small paid pilot

**Stage 1: production A/B (almost free).** On the next 6 subagent-mode plans,
override the Execution line to `claude --model opus --effort low` on every other
plan. `plan-lint` only warns about the override. Measure with the transcript
method above:

- controller cost per dispatch (baseline $0.21, 5.8 calls);
- owner nudges about running work;
- launches still unreported at handoff;
- busy-wait calls;
- whether every task has a `complete` line.

The extra cost is about $4 per Opus plan, about $13 in all.

**Stage 2: controlled replay, only if Stage 1 is ambiguous.** It reuses the
`2026-09-23-opus-5-5-effort-eval-design.md` harness.

- **Cases:** 3 completed plans with small footprints:
  - darkcloud `2026-10-06-enrichment-and-jobs-residuals-8` (5 task briefs;
    historical controller $2.22, subagents $4.69);
  - darkpanel `2026-10-17-m1-repository-tooling` (8 briefs; $4.78 and $5.27);
  - this repository's `2026-10-13-dr-forge-auto-run` (15 briefs; $7.76 and
    $16.46).
- **Workspace:** a disposable worktree at each plan's base commit, which needs
  git history for commits, rather than `git archive`. Run unattended through
  `auto-run`, as `claude -p --model <m> --effort <e> --output-format json
  --max-budget-usd <2x historical>`, with the eval note's settings isolation
  (`CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`, `CLAUDE_CONFIG_DIR` unset).
- **Arms:** Sonnet high (a fresh baseline, because the historical runs used
  older plugin versions), Opus low, and Sonnet medium. Add Opus medium only if
  Opus low shows slips that more effort might fix. That gives 3 cases x 3 arms
  x 1 repetition = 9 runs.
- **Budget:** about $125 API-equivalent: about $41 per arm at baseline rates,
  plus the Opus premium. Per arm that is about 80M controller tokens, more than
  95% of them cache reads, plus subagent work of similar dollar size.
- **Deterministic checks, no LLM grader:**
  - every task `complete` and the final review clean;
  - every review dispatched to the seat `review-route` printed;
  - no unreported background launch at handoff or finish;
  - the busy-wait call count;
  - the number of auto-run continuations needed;
  - the historical final commit's tests pass on the result tree (hidden tests,
    as in the tier eval);
  - controller cost per dispatch and per completed plan.
- **Decision rule:**
  - Switch to Opus `low` only if it has fewer tracking or protocol failures
    than Sonnet high, passes the same tests, and costs at most 1.5x per
    dispatch.
  - If Sonnet `medium` matches Sonnet high on every check, adopt Sonnet
    `medium` instead.
  - Otherwise keep Sonnet `high`.
  - With 3 cases and 1 repetition, only large differences show; treat this as a
    screen, not a measurement.

**Inline mode (secondary).** An inline session implements tasks itself,
totals 4 or less. In the tier eval, Sonnet held quality on rows 1-4, and Opus
`low` cost 1.41x Sonnet `high` on row 5 at the same pass rate. Keep inline on
Sonnet, with the existing all-heavy override to `opus high`.

## Files to change if a switch is adopted

All paths are under `plugins/dforge/`. Historical plans and specs stay as they
are.

| File | Change |
|---|---|
| `skills/writing-plans/SKILL.md` | "Choosing the Execution line" subagent bullet (about lines 168-171) and Parallel waves rule 8 (about 236-237) |
| `scripts/plan-lint` | Subagent check and WARN text, about lines 479-482 (`family = sonnet`, `effort = high`) |
| `scripts/plan-revise` | Subagent recommendation, line 380 (`rec_model=sonnet rec_effort=high`) |
| `scripts/next-step` | `launch_for` build default, line 70, and its comment. This line also drives ad hoc build launches; decide whether those change too |
| `README.md` | About line 21: "keeps the execution controller on Sonnet" |
| `tests/plan-lint.test.sh` | WARN-text assertion (line 339); subagent fixtures (61, 859, 955) |
| `tests/next-step.test.sh` | Expected launch commands (73, 242, 318, 477); fixtures (51, 397, 426, 789) |
| `tests/plan-revise.test.sh` | Subagent recommendation (about 203); add a model and effort check |
| `tests/auto-run.test.sh` | Line 130 |
| `tests/{wave,budget-line,plan-amend,inline-mode}.test.sh` | Subagent fixtures still pass, since lint only warns; update them for consistency |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | Release version bump, equal in both. The Codex launch (`codex:*` branch) is unaffected |
