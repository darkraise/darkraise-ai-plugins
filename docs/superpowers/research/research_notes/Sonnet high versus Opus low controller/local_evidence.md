# Local evidence: dforge's plan-execution controller, Sonnet 5.5 high versus Opus 5.5 low

All paths are relative to `/root/repositories/darkraise-ai-plugins`. Line numbers were read on 2026-10-18. The only web check was the Anthropic effort page, fetched 2026-10-18 to confirm quotes the controller note relies on.

## 1. The controller-model evaluation note (docs/superpowers/notes/2026-10-17-controller-model-eval.md)

### Takeaway
The note recommends **not switching yet**. It recommends a small production A/B with Opus 5.5 `low` as the only Opus arm. On paired data, it projects Opus low at about 1.4x Sonnet high's controller cost (+$4.3 per plan, +10% of plan spend). It finds that every recorded controller failure is about keeping track of background work, not about judgment, and that nothing on record shows Opus fixes that.

### Cited Findings
**The question**
- The note asks whether the subagent-mode controller should run `claude --model opus --effort low|medium` instead of `claude --model sonnet --effort high`. Status: research only, with no paid run and nothing changed. — [controller-model-eval.md:3-12](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- The answer: "Do not switch yet." Opus low "should raise the controller's cost by about 40% (about +$4 per plan, +10% of plan spend), and Opus `medium` by about 90% (about +$9, +22%)". It adds: "The controller failures on record are about keeping track of background work, not about judgment, and the harness already patches most of them. Nothing on record shows that Opus fixes them." — [controller-model-eval.md:14-21](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Pricing**
- Live prices fetched 2026-10-17, in USD per million tokens:

  | Model | Input | 5-minute cache write | 1-hour cache write | Cache read | Output |
  |---|---|---|---|---|---|
  | Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
  | Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 | $10 |

  "Opus 5.5 costs exactly 2x Sonnet 5.5 on every meter, so an Opus controller breaks even only if it uses half the tokens." The note says the `claude-api` skill's cached table (2026-10-06) still lists Sonnet 5.5 cache reads at $0.20, and that the live page wins. — [controller-model-eval.md:23-34](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Measured controller usage**
- The note counted 53 subagent-mode controller sessions from 2026-09-19 to 2026-10-17, across six repositories. All ran at effort `high`: 43 on Sonnet 5.5, 7 on Sonnet 5 and 3 on Opus 5.5. "None ran Opus at `low` or `medium`, so those settings have no direct data." — [controller-model-eval.md:59-63](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- The baseline is 15 completed plans with an all-Sonnet-5.5-high controller, covering 29 sessions. Per plan:

  | Measure | Median | Mean |
  |---|---|---|
  | Controller API calls | 307 | 284 |
  | Controller output tokens | 202k | 195k |
  | Controller cache-read tokens | 66.1M | 61.5M |
  | Controller cache-write tokens | 539k | 574k |
  | Controller cost | $11.02 | $10.39 |
  | Subagent cost (Claude seats only) | $22.17 | $31.52 |

  — [controller-model-eval.md:64-76](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- The controller is 24.8% of Claude-side plan spend; Codex work is excluded. By meter, controller cost is 59% cache reads, 19% output, and 22% cache writes plus input. "The average request re-reads about 217k tokens of context." Per subagent dispatch the controller costs **$0.21 and makes 5.8 calls**. — [controller-model-eval.md:78-82](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- The three Opus 5.5 high controller sessions carried 3 to 7 owner messages each and are "not comparable". Their output per call was 692 to 1,473 tokens, against 688 for Sonnet. — [controller-model-eval.md:83-86](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Paired Opus-versus-Sonnet data (implementer and review tasks, not controller work)**

| Comparison on the same cases | Cost ratio | Turns |
|---|---|---|
| Row 5 implementers: Opus low vs Sonnet high (10 cases, all 9/10 pass) | 1.41x | 7.2 vs 8.9 |
| Row 5 implementers: Opus medium vs Sonnet high | 1.90x | 10.6 vs 8.9 |
| Rows 3-4: Sonnet medium vs Sonnet high (equal pass rate) | 0.79-0.87x | 6.4 vs 8.6 |
| Code review: judge-opus@medium vs judge-sonnet-high | 1.86x | 18.5 vs 17.3 |

— [controller-model-eval.md:88-97](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Recorded controller slips**
- A keyword scan of 90 SDD ledgers found no controller entry for a wrong dispatch, a skipped ledger line or a fix round the controller caused. The note calls this "weak evidence" because the controller writes its own ledger. — [controller-model-eval.md:99-103](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **Busy wait.** darkcloud `dc97aea4`, 2026-09-28, Sonnet 5 high: 456 `sleep 1` calls and 293 `ListAgents` calls, for 1,240 API calls and 707M cache-read tokens. That is about $84 of controller spend against $45 for all subagents. The skill now forbids short-timeout polling. — [controller-model-eval.md:106-111](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **Stacked monitors.** darkraise-web-template `2d3533a7`, Sonnet 5.5: the owner asked "why running 7 monitors?" The controller answered "Because I stacked them. … That was sloppy". — [controller-model-eval.md:112-114](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **False "nothing running" claim.** ghr `6871f185`, Sonnet 5.5: the controller said "Nothing of mine is still running", and the owner replied that an agent and a shell were still running. The owner sent "check status" nudges in 3 more sessions. — [controller-model-eval.md:115-119](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- Harness fixes already target this class of slip: `39cc554` (never hand off or finish over work in flight), `edbeaab` (stopped work no longer counts as running), and the bounded-wait rule. "Nothing on record shows a judgment error by the controller; the ruling seat holds those calls." — [controller-model-eval.md:120-125](docs/superpowers/notes/2026-10-17-controller-model-eval.md). I confirmed the commits in git: `39cc554` dated 2026-10-09, `edbeaab` dated 2026-10-10.

**Projected cost per completed plan** (the note labels this as inference)

| Controller | Ratio vs current | Controller cost, median plan | Plan total, mean plan | Change |
|---|---|---|---|---|
| Sonnet 5.5 high (measured) | 1.00x | $11.0 | $41.9 | — |
| Opus 5.5 low | about 1.4x (range 1.2-1.6) | about $15.5 | about $46.2 | +$4.3 (+10%) |
| Opus 5.5 medium | about 1.9x (range 1.8-2.1) | about $20.9 | about $51.3 | +$9.4 (+22%) |
| Opus 5.5, same token profile as Sonnet | 2.0x | $22.0 | $52.3 | +$10.4 (+25%) |
| Sonnet 5.5 medium | about 0.8x | about $9.1 | about $40.1 | -$1.8 (-4%) |

"For Opus `low` to beat the current cost, it would need about half the controller's calls times context. The paired runs show only 19% fewer turns." — [controller-model-eval.md:127-142](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Decision rules**
- **Stage 1 (production A/B, almost free).** Over the next 6 subagent-mode plans, every other plan runs on `claude --model opus --effort low`. It measures cost per dispatch (baseline $0.21 and 5.8 calls), owner nudges, launches unreported at handoff, busy-wait calls, and whether every task has a `complete` line. The extra cost is about $13 in all. — [controller-model-eval.md:146-157](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **Stage 2 (controlled replay, only if Stage 1 is ambiguous).** It would replay 3 completed plans × 3 arms (Sonnet high, Opus low, Sonnet medium; Opus medium only if Opus low shows slips that more effort might fix) = 9 runs, for about $125 API-equivalent. The checks are deterministic, with no LLM grader. — [controller-model-eval.md:159-188](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **The Stage 2 decision rule:**
  - "Switch to Opus `low` only if it has fewer tracking or protocol failures than Sonnet high, passes the same tests, and costs at most 1.5x per dispatch."
  - Adopt Sonnet `medium` if it matches Sonnet high on every check.
  - Otherwise keep Sonnet `high`.
  - "With 3 cases and 1 repetition, only large differences show; treat this as a screen, not a measurement."

  — [controller-model-eval.md:189-197](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- **Inline mode.** Keep inline sessions on Sonnet, with the existing all-heavy override to `opus high`. — [controller-model-eval.md:199-202](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Risks the note names**
- Opus 5.5 "tends to think more per turn" than Opus 5. On long multi-part tasks, some progress updates "end the turn with text rather than a tool call". This is "the early-stop risk dforge already met in implementers (commit `7e274ec`)". — [controller-model-eval.md:44-48](docs/superpowers/notes/2026-10-17-controller-model-eval.md). `7e274ec` is "feat(superpowers): continue a reply with no status", dated 2026-09-23 (from git).
- Costs are API-equivalent; the owner may pay by subscription. — [controller-model-eval.md:57](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- The ratios come from implementer runs. "Controller work is lighter than implementation, so the real ratios could be lower or higher." — [controller-model-eval.md:129-131](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- A switch touches about 11 files. These include the writing-plans Execution rule, `plan-lint`, `plan-revise`, `next-step` (whose `launch_for` default also drives ad hoc build launches), the README, tests, and a version bump. — [controller-model-eval.md:204-221](docs/superpowers/notes/2026-10-17-controller-model-eval.md)

**Web check**
- The live effort page (fetched 2026-10-18) confirms each quote the note uses. Opus 5.5 defaults to `medium`, and Anthropic says to "Run an effort sweep on your own evals rather than carrying settings over from an earlier model". The level table lists `low` for "Simpler tasks that need the best speed and lowest costs, such as subagents". For Sonnet 5.5: "For agentic coding and multistep tool use, start with `medium` for well-specified tasks and move to `high` for harder or longer ones". The page also says "Lower effort also means fewer and terser tool calls". It gives no guidance specific to orchestrator, controller or lead-agent roles. — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)

### Inferences
- The note's argument has three parts. Opus costs 2x per token. A 2x premium is only partly offset by fewer turns (1.41x net on implementer tasks). And the controller's failure class (tracking background work) is not obviously one that more reasoning per turn fixes.
- Controller cost is dominated by cache reads (59%), which scale with calls × context. Lower effort's "fewer, terser tool calls" therefore matters most through call count. A 19% turn reduction does not offset a 2x price per token.
- The projected 1.4x (range 1.2-1.6) sits just under Stage 1's 1.5x cap. Real Opus-low controller runs could plausibly land on either side of it.

### Gaps
- No Opus low or medium controller session has ever been measured, so the per-dispatch cost and slip rate are both unmeasured (the note says so at :62-63).
- The note does not report the 15-plan baseline's per-plan slip counts, so how many failures Sonnet high produces per plan is not available in numbers.

## 2. The Opus 5.5 effort-sweep design note (docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)

### Takeaway
This is an unrun design for an effort sweep over Opus 5.5 seats: review seats, implementer seats, and the main interactive session. It does not cover the subagent-mode controller as a seat of its own. It cites Anthropic's advice to run your own effort sweep rather than carry settings over from Opus 5. The file is **untracked in git**.

### Cited Findings
- Status: "design only; no paid run made. Revisit before changing any agent's `effort:`." — [effort-eval-design.md:3-4](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)
- **Anthropic's recommendations as the note states them.** Run an effort sweep on your own evals rather than carry settings over from Opus 5. The default is `medium`. "Opus 5.5 at `medium` matches or beats Opus 5 at `high` on coding and knowledge work, and at a given level it thinks more than Opus 5 did." Sources cited: prompting-claude-opus-5-5 §Calibrate effort, and effort §Recommended effort levels for Claude Opus 5.5. — [effort-eval-design.md:6-14](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md). The 2026-10-18 fetch confirmed the default and the sweep advice. The "matches or beats Opus 5 at high" claim is not on the effort page; it may be on the prompting page, which I did not fetch.
- **Seats in scope:** `judge-opus` (then at `high`), `impl-opus-low`, `impl-opus-medium` and `impl-opus-high`, and the "main interactive session" at `high`, which it says is "covered by the implementation cases". The subagent-mode controller is not listed. — [effort-eval-design.md:18-24](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)
- **Method:** a gold corpus of 15-25 review cases and 10-15 implementation cases from git history. It sweeps `low`, `medium`, `high` and `xhigh`. The noise floor is about `1/sqrt(cases × reps)`, so 20 cases × 3 reps resolves only about ±13 points. The decision is "the lowest effort within the noise floor of the best level". — [effort-eval-design.md:26-91](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)
- **Baseline:** a 2026-09-23 replay at `high` measured 107k-129k tokens and 3-4 minutes per review. — [effort-eval-design.md:93-97](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)
- **Git status:** `git status` shows the file as untracked (`??`). Later plans instruct agents not to touch it, for example [2026-10-11-dr-forge-merge.md:24](docs/superpowers/plans/2026-10-11-dr-forge-merge.md). No `evals/effort/` directory exists. The controller note reuses its harness idea for Stage 2 ([controller-model-eval.md:159-160](docs/superpowers/notes/2026-10-17-controller-model-eval.md)), and the tier-eval spec cites it ([2026-10-01 tier-eval design:12](docs/superpowers/specs/2026-10-01-dr-superpowers-tier-eval-design.md)).

### Inferences
- The seat table is stale. `judge-opus` moved from `high` to `medium` on 2026-10-02 (section 3 below), and implementer rows were reassigned at the same time.
- The sweep as designed was absorbed into the tier eval (`evals/tiers/`). That eval measured effort only on implementer rows and review seats, never on the controller.

### Gaps
- The design note contains no Opus-low-specific findings and no measurements of controller work.

## 3. The evaluation harnesses: what has been measured and which prices are used

### Takeaway
`evals/controller/` is built and tested, but **its pilot has no data**: `pilot.tsv` holds only its header row, so Stage 1 has not started. Its decision rule defaults to keeping Sonnet unless Opus shows strictly fewer failures. The only paired Opus-versus-Sonnet data is from `evals/tiers/` (2026-10-02), on implementer and review tasks, priced by the CLI's own notional cost rather than the controller harness's price table.

### Cited Findings
**evals/controller**
- The README frames the harness as Stage 1 of the controller note: "it reads Claude Code transcripts and calls no model". It runs 6 plans, alternating and starting with `opus@low`, with the plan's `**Execution:**` line changed and committed before the first session. — [evals/controller/README.md:1-40](evals/controller/README.md)
- **Metrics:**
  - `calls` (the "baseline is 5.8 per dispatch");
  - `costPerDispatch`;
  - `sleeps` and `listAgents` (busy-wait calls);
  - `nudges`;
  - `seatMisses` (a route `review-route` printed whose next dispatch went to another seat, or never came);
  - `inFlight` (background launches still running at a handoff or session end).

  "A plan's failures are `inFlight + seatMisses + nudges`, plus one when `sleeps + listAgents` reaches 20." — [evals/controller/README.md:63-77](evals/controller/README.md)
- **Price table**, USD per million tokens from the pricing page as fetched 2026-10-17: `claude-opus-5-5` input 4, 5-minute write 5, 1-hour write 8, read 0.2, output 20; `claude-sonnet-5-5` input 2, 5-minute write 2.5, 1-hour write 4, read 0.1, output 10. Any other model is reported as `unpriced`. — [evals/controller/lib/transcript.mjs:1-7](evals/controller/lib/transcript.mjs)
- **Nudge detector:** `/check (the )?status|still running|anything (still )?running/i`. A busy-wait sleep is a bare `sleep N` command. — [transcript.mjs:12-14](evals/controller/lib/transcript.mjs)
- **Decision constants:** `BASE = 'sonnet@high'`, `CANDIDATE = 'opus@low'`, `MAX_RATIO = 1.5`, `BUSY = 20`, `MARGIN = 2`. — [evals/controller/lib/decide.mjs:4-12](evals/controller/lib/decide.mjs)
- **The Stage 1 rule:**
  - `incomplete` until each arm has 3 plans;
  - `keep` if the per-dispatch ratio is above 1.5 **or** `slips(opus) >= slips(base)`;
  - `switch` if the base has at least 2 more failures and Opus left no more plans unfinished;
  - otherwise `ambiguous`.

  — [decide.mjs:27-40](evals/controller/lib/decide.mjs)
- **No pilot data.** `evals/controller/pilot.tsv` contains only the header `plan repo arm note` (read 2026-10-18).
- **The harness reproduces the note's historical costs.** It gives $2.22 and $4.69 (darkcloud residuals-8), $4.78 and $5.27 (darkpanel m1-tooling), and $7.76 and $16.46 (dr-forge auto-run). It reports 0 seat misses on the darkcloud and dr-forge plans. — [2026-10-18-controller-model-eval plan:54-55](docs/superpowers/plans/2026-10-18-controller-model-eval.md)

**evals/tiers (repetition 1, 2026-10-02, 183 runs, notional spend $63.29)**
- The results table, with my recomputation from `results.tsv`:

  | Seat or row | Arm | Pass rate | Cost per PASS | Total cost | Turns per run |
  |---|---|---|---|---|---|
  | Row 5 implementer | Opus medium | 9/10 | $0.40 | $3.64 | 10.6 |
  | Row 5 implementer | Opus low | 9/10 | $0.30 | $2.70 | 7.2 |
  | Row 5 implementer | Sonnet high | 9/10 | $0.21 | $1.92 | 8.9 |
  | Review seat | judge-opus@high | 18 of 40 defects | — | — | — |
  | Review seat | judge-opus@medium | 18 of 40 defects | — | — | — |
  | Review seat | judge-sonnet-high | 10 of 40 defects | — | — | — |

  — [2026-10-02-tier-eval-results.md:79-104](docs/superpowers/notes/2026-10-02-tier-eval-results.md). The totals and turns are my recomputation from [evals/tiers/results/results.tsv](evals/tiers/results/results.tsv), which gives Opus low / Sonnet high = 2.70 / 1.92 = 1.41x and Opus medium = 1.90x. These match the controller note.
- **Owner rulings that followed:** row 5 moved from `impl-opus-medium` to `impl-sonnet-high`, and `judge-opus` moved from effort high to medium. Rows 3 and 4 moved from Sonnet high to Sonnet medium. — [2026-10-02-tier-eval-results.md:22-28](docs/superpowers/notes/2026-10-02-tier-eval-results.md)
- **Limits the tier eval itself names:**
  - one repetition;
  - "Cost is the CLI's notional API price, not a bill";
  - "The effort setting could not be confirmed from the CLI output; the model could";
  - written cases measure transcription more than problem-solving.

  — [2026-10-02-tier-eval-results.md:126-133](docs/superpowers/notes/2026-10-02-tier-eval-results.md)
- **How tier costs are priced:** the tier harness takes cost from `claude -p --output-format json` `total_cost_usd`, not from a local price table ([evals/tiers/README.md](evals/tiers/README.md); [effort-eval-design.md:69-70](docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md)). A grep of `evals/tiers/lib/*.mjs` for prices found none.

### Inferences
- **The Stage 1 rule leans towards keeping Sonnet.** If both arms are clean (0 failures each), `slips(opus) >= slips(base)` holds and the result is `keep`. Opus low can only win if Sonnet high produces at least 2 more tracking failures across 3 plans and Opus stays at or under 1.5x per dispatch. Opus wins only on demonstrated reliability, never on a tie.
- The 1.41x ratio applies to implementer tasks, where most cost is tool output and reasoning. The controller's cost is 59% cache reads on a roughly 217k-token resident context. Opus's 2x cache-read price applies in full there, so the controller ratio may sit nearer 2x unless Opus low makes far fewer calls. This is my inference; it is not measured.
- Because tier-eval cost came from the CLI and its effort setting "could not be confirmed", the 1.41x and 1.90x ratios carry uncertainty about whether the arms really ran at their nominal effort.
- In the tier eval, Opus low took fewer turns than Sonnet high (7.2 vs 8.9) at equal pass rates. That is the one data point in favour of the "fewer, terser tool calls" mechanism.

### Gaps
- No result files exist for the controller harness. No `evals/effort/` exists.
- Whether the CLI's notional price on 2026-10-02 used the same Sonnet cache-read rate as the live page ($0.10, versus the $0.20 in the stale skill table) is unknown. The tier results do not record per-meter tokens, so it cannot be settled locally.

## 4. Register rows 3, 23 and 24 (docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)

### Takeaway
Row 3 (evaluate Opus low/medium) is `done`: the evaluation harness was delivered. The actual decision lives in row 23, which is `open` and waits on the 6-plan pilot. Row 24 (the Stage 2 replay) is `deferred`, because a plan review found the note's three replay cases unusable and listed safeguards a future Stage 2 must have.

### Cited Findings
- **Row 3.** Item: "Evaluate to use opus low/medium as controller instead of sonnet high, since I see that in claude code cloud, it always use opus low/medium as controller." It is assigned to `docs/superpowers/plans/2026-10-18-controller-model-eval.md`. Acceptance: the harness measures cost, slips, seat routing and per-task completion, and `pilot-report.mjs` prints the Stage 1 decision. State `done`, with the note "owner closed on 2026-10-18; the Stage 1 decision itself is tracked by row 23". — [register:10](docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)
- **Row 23.** "Run the controller pilot: Stage 1 on the next 6 subagent-mode plans (pilot.tsv, alternating opus@low and sonnet@high), Stage 2 replays if Stage 1 is ambiguous; owner decides keep or switch". State `open`. — [register:30](docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)
- **Row 24.** "Plan and build the Stage 2 controlled replay harness … only if the Stage 1 pilot ends ambiguous". State `deferred`. The owner deferred it on 2026-10-18 after plan review round 1 found the three cases unusable:
  - darkcloud residuals-8 runs proofs in the original repository's worktree, uses shared `/var/tmp/dc-proof-r8` and an old plugin path, and redeploys the real stack;
  - darkpanel m1-tooling Task 10 pushes to GitHub, changes a repository setting and waits on live CI;
  - the dforge migration rewrites `dr-forge:` literals that the dr-forge auto-run case's hidden test asserts.

  Requirements for a future Stage 2:
  - choose cases with none of these problems;
  - smoke-test the Stop hook and cockpit under `claude -p` first;
  - require every case-by-arm cell before deciding;
  - adopt Sonnet medium only when it matches case by case (busy waits under 20, continuations and cost included);
  - give fixtures and replays a temporary HOME;
  - prove the hidden tests ran (`DARKPANEL_REQUIRE_UI`, `DARKCLOUD_REQUIRE_PRIVILEGED_TESTS`);
  - check budget before each invocation and after each compaction;
  - keep usage-limit endings distinct from failed compactions;
  - sum cost across retries;
  - make a preflight failure row retryable.

  — [register:31](docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)
- **Related deferred harness defects:** row 27 (a Bash result with `is_error` drops a ledger write from the same command) and row 28 (`PER_TASK` needs a literal `scripts/` prefix; no test reaches the `unpriced` status). — [register:34-35](docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)

### Inferences
- In practice, the Sonnet-high versus Opus-low question is undecided and has no new data since 2026-10-17. Its next step is real production plans, not a paid replay.

### Gaps
- None for this question.

## 5. What the controller does: decision kinds, judgment versus procedure, and failure modes

### Takeaway
By design the controller is a **coordinator with judgment taken away**. It reads only the plan header and one task brief at a time. It runs scripts that print the next seat, writes the ledger, waits on background work, and carries out the ruling seat's verdicts verbatim. Every judgment about the plan, the spec or a finding goes to a separate ruling seat (judge-opus at medium). What remains for the controller is long-horizon bookkeeping and a handful of small classification calls. Its documented failures are all in bookkeeping: busy waiting, stacked monitors, false "nothing running" claims, and work left in flight at handoff.

### Cited Findings
**The design intent**
- "Judgment belongs to the ruling seat, never to you, whatever model you run on. It reads the whole plan, the spec, `amendments.md` and the ledger; you read the header and one brief at a time." — [subagent-driven-development/SKILL.md:397-399](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- The Execution-line rule says: `subagent` → `claude --model sonnet --effort high`. "The controller owns no judgment calls — the ruling seat does — so it needs no stronger model." — [writing-plans/SKILL.md:168-171](plugins/dforge/skills/writing-plans/SKILL.md). The same default is hard-coded in `launch_for` ([plugins/dforge/scripts/next-step:63-71](plugins/dforge/scripts/next-step)). The README says the plugin "keeps the execution controller on Sonnet" because "The main session was 92% of token spend, most of it re-reading a 400–700k context" ([plugins/dforge/README.md:17-21](plugins/dforge/README.md)).
- **Rulings, not stalls.** "You decide the mechanical problems yourself — the dispatch-problems table, resuming or re-dispatching by cache state, batching, a report missing a required section, a tool failure … Everything that needs judgment about the plan, the spec or a finding goes to the ruling seat." — [SKILL.md:97-105](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Only four things stop the run:** an irreversible operation; a security-sensitive action; an outside-the-worktree side effect such as a merge, push or publish; and a ruling-seat `BLOCKED`. — [SKILL.md:107-112](plugins/dforge/skills/subagent-driven-development/SKILL.md)

**Procedural decisions (scripted or rule-driven)**
- **Setup:** isolated worktree; one finish-preference question; `sdd-workspace`; ledger identity line; register rows set to `doing`; header only via `task-brief --header`; one `preflight` item to the ruling seat. — [SKILL.md:205-288](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Routing:** reviewers, rulings, the final review and final fixes go to whatever seat `scripts/review-route` prints. Fleet agents never get a `model` or `effort` argument. — [SKILL.md:290-307](plugins/dforge/skills/subagent-driven-development/SKILL.md); [delegated-task.md:21-37](plugins/dforge/reference/delegated-task.md)
- **Implementer dispatch:** the brief file, a report-file path, no pasted history, no parallel implementers outside waves. The "dispatch problems" table is resolved by rule: missing Implementer line → score with the ladder rubric; model unavailable → same effort one model down. — [delegated-task.md:43-110](plugins/dforge/reference/delegated-task.md)
- **The fix loop:**
  - rounds 1-3 resume or start fresh by a numeric cache rule (`t1 − t0 < 300` seconds, or context under about 100k tokens);
  - rounds 4-5 escalate to the successor rung, and a non-improving progress score escalates early;
  - the breaker at round 5 goes to the ruling seat;
  - "Never fix findings yourself in the controller session".

  — [delegated-task.md:268-372](plugins/dforge/reference/delegated-task.md)
- **Carrying out verdicts:** CONFIRMED-GAP, PARK, AMEND (via `scripts/plan-amend`) and BLOCKED. "Never soften, merge or second-guess a verdict." — [SKILL.md:427-460](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Session budget:** obey the `ok`, `handoff` or `unknown` verdict printed by `task-brief` and `review-package`, not the percentage. — [SKILL.md:462-491](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **The executor lane:**
  - run the Codex wrapper yourself as a background Bash call with a computed `timeout`;
  - write a provisional `thread pending` ledger line before launch, then the real thread id;
  - read a cut foreground call correctly ("a controller reading that as a Codex failure has misdiagnosed its own harness").

  — [executor-lane.md:117-145](plugins/dforge/reference/executor-lane.md), [:200-224](plugins/dforge/reference/executor-lane.md)
- **Handoff and finish:** reconcile live children (wait for them, or `TaskStop` them with a Ruling) before handoff, then run `scripts/next-step` as the last action. Finishing is a Skill tool call in the same turn. — [SKILL.md:114-124](plugins/dforge/skills/subagent-driven-development/SKILL.md), [:558-563](plugins/dforge/skills/subagent-driven-development/SKILL.md)

**Residual judgment-like calls left to the controller**
- **NEEDS_CONTEXT:** decide whether the answer is mechanical (supply it) or a question about plan meaning (send it to the seat). "You never answer a requirements question from your own reading of one brief." — [delegated-task.md:121-128](plugins/dforge/reference/delegated-task.md)
- **BLOCKED triage:** decide between a context problem, more reasoning needed (escalate), too large (send to seat for a split), or the plan is wrong (send to seat). — [delegated-task.md:130-134](plugins/dforge/reference/delegated-task.md)
- **DONE_WITH_CONCERNS:** decide whether concerns are about correctness or scope (pass them to the reviewer) or are observations. — [delegated-task.md:119](plugins/dforge/reference/delegated-task.md)
- **No status line:** send up to two continuations, then treat the task as BLOCKED. — [delegated-task.md:144-158](plugins/dforge/reference/delegated-task.md)
- **Batching:** decide from the briefs whether contiguous tasks are "small, independent edit[s] of the same kind". — [SKILL.md:495-504](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Composing a dispatch:** include "interfaces and decisions from earlier tasks that the brief cannot know", the verdicts that bear on the task, and a pointer to parked findings. Send an ambiguity noticed in the brief to the seat as a `plan-conflict` item. — [delegated-task.md:62-74](plugins/dforge/reference/delegated-task.md), [:90-91](plugins/dforge/reference/delegated-task.md)
- **Recognising plan conflicts:** decide whether a review finding "conflicts with what the plan's text requires", which routes it to the seat. — [delegated-task.md:281-286](plugins/dforge/reference/delegated-task.md)
- **Choosing a model for general-purpose seats:** "Scoped re-reviews of small fix diffs take a cheap-to-mid tier; a subtle concurrency fix takes more." — [SKILL.md:304-307](plugins/dforge/skills/subagent-driven-development/SKILL.md)

**Judgment-heavy work delegated away from the controller**
- The ruling seat handles these kinds of items: `preflight`, `plan-conflict`, `cannot-verify`, `breaker`, `blocked-plan`, `executor-empty-diff` and `final-residual`. — [SKILL.md:401-412](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- Header amendments get a second, independent judge-opus confirmation. — [SKILL.md:444-454](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- Task reviews and the final whole-branch review go to judge or Codex seats.
- In an auto run, a ruling-seat `BLOCKED` goes to a Fable batch instead of stopping. — [SKILL.md:42-50](plugins/dforge/skills/subagent-driven-development/SKILL.md)

**Documented failure modes and the rules written against them**
- **Lost place after compaction.** Controllers that lost their place "have re-dispatched entire completed task sequences — the single most expensive failure observed". The mitigation is the ledger plus the recovery table. — [SKILL.md:221-224](plugins/dforge/skills/subagent-driven-development/SKILL.md), [:367-393](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Busy waiting.** "never poll a wait interface with short timeouts, and never sit in one silent, open-ended wait either". The skill prescribes bounded 5-10 minute stretches via `Monitor` with an until-loop, "never a background `sleep`", and says to `TaskStop` the monitor before handoff. — [SKILL.md:510-523](plugins/dforge/skills/subagent-driven-development/SKILL.md)
- **Leftover child processes.** An implementer that left background work "stays listed after it reports"; stop it with `TaskStop`. `scripts/in-flight` lists any the controller missed. — [delegated-task.md:136-142](plugins/dforge/reference/delegated-task.md)
- **Ending on a progress note.** An implementer ends its turn on a progress note instead of a status. The fix is continuations (commit `7e274ec`). — [delegated-task.md:144-158](plugins/dforge/reference/delegated-task.md)
- **Bloated dispatches.** "a real session's dispatch hit 42k chars of which 99% was pasted history". — [delegated-task.md:79-84](plugins/dforge/reference/delegated-task.md)
- **Missed review seats.** These are not documented as observed incidents. They are measured as `seatMisses` in the harness, and 0 were found on the replay plans checked. — [README.md:73](evals/controller/README.md); [2026-10-18 plan:55](docs/superpowers/plans/2026-10-18-controller-model-eval.md)
- **Monitor stacking, false "nothing running" claims and owner nudges.** — section 1 above ([controller-model-eval.md:112-119](docs/superpowers/notes/2026-10-17-controller-model-eval.md)).
- **Turn count versus price.** delegated-task.md says "Turn count beats token price … the cheapest models routinely take 2-3× the turns on multi-step work". — [delegated-task.md:39-41](plugins/dforge/reference/delegated-task.md). This is written about reviewer seats, not the controller.

### Inferences
- The controller's workload is long-horizon state tracking: a ledger, background children, bounded waits, compaction recovery, and many cache-read-heavy calls. Its residual judgment calls are light classification calls. The repository's design explicitly argues that model strength buys little here, because judgment is routed to the ruling seat.
- The failure modes on record could in principle respond to a more careful model, because they are lapses of attention or diligence over a long session. But the repository has no evidence either way. The three Opus-high controller sessions are not comparable, and no Opus-low session exists.
- Opus 5.5 at low effort has a known risk: ending a turn on a text progress update. That directly conflicts with the controller's "Continuous execution" rule ([SKILL.md:95](plugins/dforge/skills/subagent-driven-development/SKILL.md)) and with the auto-run rule that a turn ends only on specific lines ([SKILL.md:64-65](plugins/dforge/skills/subagent-driven-development/SKILL.md)). An early stop would show up as extra owner nudges or auto-run continuations.

### Gaps
- No repository file classifies the controller's decisions by how often they occur, so how much of controller spend goes to the residual judgment calls is unknown.
- No recorded incident shows a controller misclassifying NEEDS_CONTEXT or BLOCKED. Whether such errors happen and go unlogged is unknown, because the controller writes its own ledger.

## 6. Statements that Claude Code cloud uses Opus low/medium as its controller

### Takeaway
The only source in the repository is the owner's own observation, which is recorded twice and explicitly marked unverified. No document, measurement or citation backs it.

### Cited Findings
- The register says: "since I see that in claude code cloud, it always use opus low/medium as controller". — [register:10](docs/superpowers/registers/2026-10-17-run-order-finish-controller.md)
- The note says: "The owner reports that Claude Code cloud uses Opus at low/medium as its controller; this is unverified and taken here as their observation." — [controller-model-eval.md:11-12](docs/superpowers/notes/2026-10-17-controller-model-eval.md)
- A repository-wide grep for "claude code cloud", "code cloud", "cloud" next to "controller", and "low/medium" found nothing else relevant. The other hits were unrelated Codex and executor model tables.

### Inferences
- Even if the claim is true, a cloud product's choice may reflect different pricing (for example, subscription capacity rather than API price), a different task mix, or a different harness. The repository has nothing that maps it onto dforge's controller.

### Gaps
- Unverified. Settling it would take Anthropic documentation for Claude Code on the web, or a transcript of a cloud session showing the model and effort. Neither is in the repository.

## 7. What the local evidence implies for Sonnet 5.5 high versus Opus 5.5 low

### Takeaway
Locally, the case for keeping Sonnet high rests on cost (Opus is 2x per token, projected about 1.4x net) and on a design that routes judgment away from the controller. The case for Opus low rests only on its fewer turns in implementer runs and on the untested idea that it might track background work better. No controller-specific Opus-low data exists, and the pilot that would produce it (register row 23) has 0 of 6 plans recorded.

### Cited Findings
- **Cost:**
  - Opus low projects to about $15.5 per median plan against $11.0 for Sonnet high, +10% of total plan spend ([controller-model-eval.md:133-142](docs/superpowers/notes/2026-10-17-controller-model-eval.md)).
  - Breaking even would need about half the calls × context; the paired runs show 19% fewer turns ([controller-model-eval.md:141-142](docs/superpowers/notes/2026-10-17-controller-model-eval.md)).
  - Sonnet medium is the cheaper candidate at about 0.8x ([controller-model-eval.md:139](docs/superpowers/notes/2026-10-17-controller-model-eval.md)).
- **Quality on paired implementer tasks:** Opus low equalled Sonnet high's pass rate, 9 of 10 each ([2026-10-02-tier-eval-results.md:79-85](docs/superpowers/notes/2026-10-02-tier-eval-results.md)). On reviews, Opus at medium found 18 of 40 defects against Sonnet high's 10 of 40 ([tier-eval-results.md:100-104](docs/superpowers/notes/2026-10-02-tier-eval-results.md)). That is a judgment-quality gap, but in a seat the controller does not hold.
- **The decision machinery:** a switch needs Opus at 1.5x or less per dispatch **and** at least 2 fewer failures than Sonnet across at least 3 plans per arm. A tie keeps Sonnet. — [decide.mjs:31-40](evals/controller/lib/decide.mjs)

### Inferences
- The tier eval shows Opus out-judging Sonnet on reviews. That would matter for the controller only if the controller made rulings, and by design it does not. This weakens "Opus is smarter" as an argument for this seat.
- The open empirical question is whether Opus low reduces tracking failures (nudges, in-flight leftovers, busy waits) enough to justify about +40% controller cost. Its known early-stop tendency could raise those same counts. Only the Stage 1 pilot can settle this.
- Sonnet medium, an arm the note added, is the change the existing evidence supports most directly. On implementer rows it held pass rate at 0.79-0.87x cost, and the Anthropic guidance for well-specified agentic work points to it. Stage 1's code compares only `opus@low` against `sonnet@high`, though. A Sonnet-medium arm exists only in the deferred Stage 2.

### Gaps
- There are no controller sessions at Opus low or medium, and no pilot rows. The real per-dispatch ratio and slip rates are unknown until register row 23 runs.
