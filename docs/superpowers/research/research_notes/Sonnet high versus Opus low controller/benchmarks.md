# Benchmarks: Opus 5.5 and Sonnet 5.5 across effort levels, for a coding-agent controller

Research date: 2026-10-18. Opus 5.5 released 2026-09-22; Sonnet 5.5 released 2026-09-28. Every number below carries its effort setting where the source states one. Anthropic's launch numbers are vendor-reported; Artificial Analysis (AA) numbers are an independent harness and must not be mixed with Anthropic's in one column.

## Q1. What does Anthropic itself publish for Opus 5.5 and Sonnet 5.5, and which numbers are per effort level?

### Takeaway
Anthropic's launch tables report one headline score per benchmark, mostly at max effort (Opus Terminal-Bench at xhigh), and show effort only as score-vs-cost charts with a few numbers called out in text. Most of the benchmarks in the brief (SWE-bench Verified/Pro, tau2-bench, MCP Atlas, BrowseComp, ARC-AGI, GPQA) do not appear in either 5.5 launch post.

### Cited Findings
Opus 5.5 launch table (2026-09-22). Opus 5.5 at max effort with adaptive thinking unless noted:
- Terminal-Bench 4.0: Opus 5.5 66.4% (xhigh, ±2.6 pts standard error), Fable 5.1 55.8%, Opus 5 52.3%, GPT-6 Astra 57.9% (high, as reported by OpenAI), GPT-5.6 Sol 37.3% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- FrontierCode v1.1 (Main): Opus 5.5 54.4%, Fable 5.1 50.3%, Opus 5 48.0%, GPT-6 Astra 53.3% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- CursorBench 4.0: Opus 5.5 57.8%, Fable 5.1 51.8% (max), Opus 5 46.6% (max), GPT-5.6 Sol 41.7% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- GDPval-AA v2.1: Opus 5.5 1846 Elo, Fable 5.1 1735, Opus 5 1708, GPT-6 Astra 1542 — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- AutomationBench (Zapier; no fallback models, so safeguard interventions count as failures): Opus 5.5 40.0%, Fable 5.1 31.4%, Opus 5 26.9%, GPT-6 Astra 41.4% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- Humanity's Last Exam (with tools): Opus 5.5 67.7%, Fable 5.1 65.6%, Opus 5 63.6%, GPT-6 Astra 57.2% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- Terminal-Bench-Science 0.1: Opus 5.5 58.7%, GPT-6 Astra 64.6% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- OSWorld 2.1 (partial): Opus 5.5 81.8%, Fable 5.1 80.7%, Opus 5 74.0% — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)

Sonnet 5.5 launch table (2026-09-28). Effort is mostly unstated:
- Terminal-Bench 4.0: Sonnet 5.5 70.6% (effort not stated), Sonnet 5 10.3%, Opus 5.5 66.4% (xhigh) — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- FrontierCode 1.1 (Main): Sonnet 5.5 46.2% (max) and 52.1% (xhigh); Sonnet 5 42.4%; Opus 5.5 54.4%; GPT-6 Sol 49.3% — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- CursorBench 4.0: Sonnet 5.5 55.5%, Sonnet 5 34.1%, Opus 5.5 57.8% — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- GDPval-AA v2.1: Sonnet 5.5 1844, Opus 5.5 1846. AA-Briefcase v1.1: Sonnet 5.5 1811, Opus 5.5 1822 — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- Humanity's Last Exam (with tools): Sonnet 5.5 64.5%, Opus 5.5 67.7%. OSWorld 2.1 (partial): Sonnet 5.5 80.1%, Opus 5.5 81.8% — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- Orchestration-relevant footnote: Sonnet 5.5 scored lower at max than at xhigh on FrontierCode because at max it more often ran a code-review skill that spawns many subagents, causing timeouts or out-of-scope edits in two cases — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)

Effort defaults: medium in Claude Code and the Claude apps, high on the Claude Platform API — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5). The default model in Claude Code remains Opus 5.5 — [Apidog, 2026-09-29](https://apidog.com/blog/claude-sonnet-5-5-claude-code/)

Pricing per million tokens: Opus 5.5 $4 input / $20 output; Sonnet 5.5 $2 / $10 — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5); [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)

Qualitative agentic claims from launch customers (vendor-selected, not benchmarks):
- Opus 5.5: Column says it "delegates to subagents far more effectively and checks its own work"; Clio says it "stayed on task for over 18 hours"; Viktor reports fewer steps and tool calls per task than Opus 5; Anthropic says it is "much less likely than recent models to take hard-to-reverse actions or act outside the boundaries it's been given" — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- Sonnet 5.5: batches tool calls more than Sonnet 5; Lovable reports about a third fewer tool calls; Base44 reports the fewest failed tool calls among the models it compared and says it "rarely stopped to ask the user questions"; first Sonnet to finish Pokémon Red from screenshots only — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)

Unverified third-party figures: llm-stats lists SWE-bench Pro 89.9% for Opus 5.5, which I could not match to any Anthropic material. The only MCP Atlas figure found, 85.8% at xhigh, is for Opus 5, not 5.5 — [llm-stats](https://llm-stats.com/blog/research/claude-opus-5-5-launch); [MCP Playground](https://mcpplaygroundonline.com/models/claude-opus-5)

### Inferences
- On Anthropic's own agentic-coding numbers, top-effort Sonnet 5.5 is level with or ahead of top-effort Opus 5.5 on Terminal-Bench 4.0 (70.6% against 66.4%), and within about 2 points on CursorBench, OSWorld and GDPval. The gap between the models appears mainly at lower effort settings (see Q2).
- The FrontierCode footnote is the only published evidence about orchestration behavior that varies with effort: at max effort, Sonnet 5.5 over-delegated to subagents and lost score. That is a failure mode a controller must avoid.

### Gaps
- SWE-bench Verified, SWE-bench Pro, tau2-bench / tau-bench, MCP Atlas, BrowseComp, ARC-AGI, GPQA and instruction-following benchmarks (for example IFBench) for Opus 5.5 or Sonnet 5.5: not found in either launch post or any primary source I reached. The system cards were not reached.
- Effort levels for most Sonnet 5.5 table entries, including Terminal-Bench 70.6%, are not stated.

## Q2. Effort curves: score against effort and tokens. Where does Opus 5.5 low sit relative to Sonnet 5.5 high?

### Takeaway
On both per-effort data sets found, Sonnet 5.5 at high scores above Opus 5.5 at low on agentic tasks: Artificial Analysis gives Terminal-Bench 4.0 at 44% against 31% and its Intelligence Index at 47 against 42; Cursor gives CursorBench 47.8% against 43.7%. Opus low uses far fewer output tokens per task and costs less to run. Opus 5.5 at medium beats Sonnet 5.5 at high on almost every metric, at roughly 1.6 to 1.7 times the cost.

### Cited Findings
Artificial Analysis Intelligence Index v4.3.2, per effort configuration (all labelled "Default Fallback"). Pages read 2026-10-18:

| Config | AA Index | Terminal-Bench 4.0 | AutomationBench-AA | GDPval-AA v2.1 | AA-Briefcase v1.1 | HLE | SciCode | AA-LCR v1.1 | CritPt | AA-Omniscience | Output tokens per task | Tokens to run index | Cost to run index | Speed (tok/s) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Sonnet 5.5 low | 36 | 21% | 49% | 1175 | 1272 | 36% | 49% | 76% | not given | 19 | 14k | 23M | $482 | 110 |
| Sonnet 5.5 medium | 41 | 30% | 55% | 1323 | 1441 | 40% | 53% | 76% | not given | 20 | 21k | 31M | $622 | 109 |
| Sonnet 5.5 high | 47 | 44% | 59% | 1549 | 1636 | 46% | 54% | 78% | 25% | 21 | 37k | 52M | $1,027 | 111 |
| Sonnet 5.5 max | 56 | 63.6% | not given | 1844 | 1811 | not given | not given | not given | not given | 54% accuracy | ~193k | not given | ~$7.60 per task | not given |
| Opus 5.5 low | 42 | 31% | 53% | 1235 | 1280 | 48% | 59% | 81% | 18% | 39 | 10k (3k reasoning) | 20M | $860 | 80 |
| Opus 5.5 medium | 51 | 53% | 61% | 1584 | 1625 | 55% | 59% | 84% | 28% | 40 | 26k | 38M | $1,627 | 82 |
| Opus 5.5 high | 54 | 57% | 63% | 1704 | 1686 | 56% | 60% | 83% | 31% | 41 | 36k | 53M | $2,172 | 83 |
| Opus 5.5 max | 58 | 59.6% | not given | 1846 | 1822 | 61.4% | 66.9% | not given | not given | 66% accuracy | ~119k | 260M | $5.98 per task | 97 |

Sources for each row:
- Sonnet low — [AA](https://artificialanalysis.ai/models/comparisons/claude-sonnet-5-5-low-vs-step-5)
- Sonnet medium — [AA](https://artificialanalysis.ai/models/comparisons/claude-sonnet-5-5-medium-vs-step-5)
- Sonnet high — [AA](https://artificialanalysis.ai/models/comparisons/claude-sonnet-5-5-high-vs-step-5)
- Sonnet max, from the AA Sonnet 5.5 article (2026-09-29) as summarised by NYU Shanghai RITS. The AA article itself was not fetched directly — [RITS](https://rits.shanghai.nyu.edu/ai/claude-sonnet-5-5-ranks-2-at-56-behind-only-opus-5-5/)
- Opus low — [AA](https://artificialanalysis.ai/models/comparisons/claude-opus-5-5-low-vs-step-5)
- Opus medium — [AA](https://artificialanalysis.ai/models/comparisons/claude-opus-5-5-medium-vs-step-5)
- Opus high — [AA](https://artificialanalysis.ai/models/comparisons/claude-opus-5-5-high-vs-step-5)
- Opus max — [AA article](https://artificialanalysis.ai/articles/claude-opus-5-5); [AA model page](https://artificialanalysis.ai/models/claude-opus-5-5)

Not fetched: the Opus 5.5 xhigh and Sonnet 5.5 xhigh AA pages. A comparison URL for Opus xhigh exists — [AA](https://artificialanalysis.ai/models/comparisons/claude-opus-5-5-xhigh-vs-step-5)

- AA places Opus 5.5 medium, high, xhigh and max on the intelligence-vs-cost-per-task Pareto frontier. Opus 5.5 low is not on it — [AA article](https://artificialanalysis.ai/articles/claude-opus-5-5)
- AA says Sonnet 5.5 at max used about 193k output tokens per task, the most AA has measured, at about $7.60 per task — [RITS summary of AA](https://rits.shanghai.nyu.edu/ai/claude-sonnet-5-5-ranks-2-at-56-behind-only-opus-5-5/)

CursorBench 4.0 per effort. The source says Cursor measured the scores in its own harness and the per-task costs come from Anthropic's launch charts:

| Effort | Sonnet 5.5 | Opus 5.5 |
|---|---|---|
| low | 35.8% at $0.50 | 43.7% at $1.17 |
| medium | 39.2% at $0.70 | 52.5% at $2.91 |
| high | 47.8% at $1.67 | 56.0% at $3.97 |
| xhigh | 53.1% at $3.88 | 56.0% at $6.98 |
| max | 55.5% at $9.67 | 57.8% at $13.43 |

Source: [Apidog, 2026-09-29](https://apidog.com/blog/claude-sonnet-5-5-claude-code/). The max values (55.5%, 57.8%) and Opus medium (52.5%) match the numbers in Anthropic's launch text, which partially corroborates the table — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)

Anthropic's effort statements (charts with few numbers):
- Opus 5.5 at default (medium) effort beats Opus 5 at max on Terminal-Bench 4.0 for about a fifth of the cost. FrontierCode at medium: 54.6%. CursorBench at medium: 52.5%. On GDPval-AA, Opus 5.5 at medium beats GPT-6 Astra at max for about a fifth of the cost. On AutomationBench it beats Opus 5 at every effort level — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)
- Sonnet 5.5 at low or medium beats Sonnet 5's best Terminal-Bench score at about a tenth of the cost. At high, it matches GPT-6 Sol's best FrontierCode score at about a fifth of the cost. Anthropic says Sonnet 5.5 "complements Opus 5.5 best at lower effort", and that at higher settings it can perform comparably at a similar cost — [Anthropic, Sonnet 5.5](https://www.anthropic.com/news/claude-sonnet-5-5)
- Customer effort data points for Opus 5.5: Deloitte caught 72% of known bugs at the lowest effort, against 56% for Opus 5 at high. Factory found medium matched Opus 5 at high with 20 to 25% fewer output tokens. Rogo found the lowest effort beat Opus 5 at high on BigFinance Bench with about 60% fewer output tokens — [Anthropic, Opus 5.5](https://www.anthropic.com/news/claude-opus-5-5)

Conflict on token efficiency: Anthropic says Opus 5.5 uses fewer tokens per task and costs about 40% less than Opus 5 at default settings — [Anthropic](https://www.anthropic.com/news/claude-opus-5-5). AA measured about 119k output tokens per task at max, about 1.6 times Opus 5's ~73k, with cost per task level with Opus 5 — [AA article](https://artificialanalysis.ai/articles/claude-opus-5-5). The two compare different settings (default against max), so they need not contradict each other, but they should not be quoted together without that caveat.

Harness conflict on Terminal-Bench 4.0: Anthropic reports Sonnet 70.6% and Opus 66.4% (xhigh). AA's own runs give Sonnet 63.6% and Opus 59.6% (max) — [RITS summary of AA](https://rits.shanghai.nyu.edu/ai/claude-sonnet-5-5-ranks-2-at-56-behind-only-opus-5-5/)

### Inferences
- Opus 5.5 low against Sonnet 5.5 high on AA:
  - Sonnet high wins clearly on the agentic and tool-use items: Terminal-Bench 4.0 (+13 points), AutomationBench-AA (+6), GDPval-AA (+314 Elo), AA-Briefcase (+356 Elo), and CritPt (+7).
  - Opus low wins on knowledge and long-context items: AA-LCR (+3), HLE (+2), SciCode (+5), and AA-Omniscience (39 against 21).
  - Opus low uses about 3.7 times fewer output tokens per task (10k against 37k), costs about 16% less to run the index, and generates about 28% slower (80 against 111 tok/s). Because it writes far fewer tokens, its wall-clock time per turn is probably still shorter (inference, not measured).
- On CursorBench the same ordering holds: Sonnet high 47.8% at $1.67, Opus low 43.7% at $1.17.
- Opus 5.5 at low effort spends about 3k reasoning tokens per task on AA. That fits the user's framing of effort as "how careful it thinks": low effort mainly cuts deliberation, and on multi-step agentic benchmarks Opus low drops 22 points on Terminal-Bench relative to Opus medium (31% against 53%), a much larger loss than on knowledge benchmarks (HLE 48% against 55%).
- Opus 5.5 at medium dominates Sonnet 5.5 at high on AA: higher on every metric listed except AA-Briefcase (1625 against 1636), with fewer tokens per task (26k against 37k) but higher cost ($1,627 against $1,027). If both candidates were allowed to move by one effort level, Opus medium is the stronger alternative to either.
- Agentic benchmarks (Terminal-Bench, AutomationBench, GDPval, Briefcase) are the closest proxy to orchestration in this data. All of them favor Sonnet high over Opus low.

### Gaps
- Anthropic's score-vs-cost charts are images. The exact per-effort points for Terminal-Bench 4.0, FrontierCode, GDPval and AutomationBench were not extractable, apart from the few numbers quoted in text.
- AA's xhigh configurations for both models were not fetched.
- No per-effort data was found for tau2-bench, MCP Atlas or any instruction-following benchmark.

## Q3. Third-party evaluations (AA, LMArena, Vals.ai, Epoch, SWE-bench and Terminal-Bench leaderboards, Aider)

### Takeaway
Artificial Analysis is the only third party found with full per-effort data (see Q2). It ranks Opus 5.5 max first (58) and Sonnet 5.5 max second (56). Nothing was retrieved from LMArena, Vals.ai, Epoch AI, swebench.com, tbench.ai or Aider polyglot for the 5.5 models.

### Cited Findings
- AA Intelligence Index v4.3.2 has 10 evaluations: AA-Briefcase v1.1, GDPval-AA v2.1, AutomationBench-AA, Terminal-Bench 4.0, SciCode, HLE, GDP.pdf, CritPt, AA-Omniscience, AA-LCR v1.1. Opus 5.5 max is ranked #1 of 217 at 58, ahead of GPT-6 Astra and Fable 5.1, tied at 53 — [AA model page](https://artificialanalysis.ai/models/claude-opus-5-5); [AA article](https://artificialanalysis.ai/articles/claude-opus-5-5)
- Sonnet 5.5 max is #2 at 56. Sonnet 5 scored 38 at max — [RITS summary of AA, 2026-09-29](https://rits.shanghai.nyu.edu/ai/claude-sonnet-5-5-ranks-2-at-56-behind-only-opus-5-5/)
- AA max-effort output tokens per task: Opus 5.5 ~119k, Opus 5 ~73k, Fable 5.1 ~78k, GPT-6 Astra ~27k — [AA article](https://artificialanalysis.ai/articles/claude-opus-5-5)
- Note: AA's separate "Agentic Index" and "Coding Index" were not shown for these models on the pages fetched. AA presents Terminal-Bench 4.0 as its agentic coding evaluation — [AA](https://artificialanalysis.ai/models/comparisons/claude-opus-5-5-low-vs-step-5)

### Inferences
- Because AA runs every effort configuration as a separate listed model, it is the best available source for an Opus-low-against-Sonnet-high comparison on identical harnesses.

### Gaps
- LMArena or WebDev Arena Elo, Vals.ai, Epoch AI, the SWE-bench leaderboard, the Terminal-Bench leaderboard (tbench.ai) and Aider polyglot for Opus 5.5 or Sonnet 5.5: not found, because I did not reach them within the tool budget. Fetching each site's leaderboard page directly would settle this.

## Q4. Multi-agent and orchestration evidence: orchestrator against worker model, and how effort affects reliability

### Takeaway
Anthropic's documented pattern is a stronger model as orchestrator with cheaper workers (historically Opus lead with Sonnet subagents). For the 5.5 generation it documents both "Opus orchestrates Sonnet workers" and "Sonnet executes and consults Opus as advisor". No study was found that tests orchestrator effort level directly. Evidence on whether more reasoning effort improves tool-call reliability is mixed.

### Cited Findings
- Historical (Opus 4 / Sonnet 4, 2025-06-13): Anthropic's multi-agent research system, with an Opus 4 lead and Sonnet 4 subagents, beat single-agent Opus 4 by 90.2% on an internal research eval of about 20 queries — [Anthropic Engineering](https://www.anthropic.com/engineering/multi-agent-research-system)
  - On BrowseComp, three factors explained 95% of performance variance: token usage alone explained 80%, and the number of tool calls plus the model choice explained the rest.
  - Upgrading from Sonnet 3.7 to Sonnet 4 gave a larger gain than doubling Sonnet 3.7's token budget. This is a "model over budget" trend signal.
  - Orchestrator failure modes: spawning 50 subagents for simple queries, and vague one-line delegations that led to duplicated work. The fix was to give each subagent an objective, an output format, tool guidance and boundaries, plus explicit rules that scale effort to query complexity.
- 5.5 generation patterns: (1) Sonnet 5.5 executes and consults Opus 5.5 on hard decisions through the advisor tool (beta); (2) Opus 5.5 splits the job and passes bulk subtasks to Sonnet 5.5 workers. The article presents both as Anthropic-documented — [MyClaw, 2026-09-29](https://myclaw.ai/blog/sonnet-5-5-vs-opus-5-5)
- Claude Code guidance: keep Opus as the main model and set `CLAUDE_CODE_SUBAGENT_MODEL=claude-sonnet-5-5` for subagents. In `opusplan` mode, Opus plans and Sonnet executes — [Apidog](https://apidog.com/blog/claude-sonnet-5-5-claude-code/)
- Worker-only benchmark (Ovidius AI, published 2026-10-09; runs 2026-09-29 to 2026-10-08): 458 graded runs of Haiku, Sonnet and Opus 5.5 as Claude Code subagents across 23 task types, including an effort grid at low, medium and high — [Ovidius](https://www.ovidius.ai/blog/claude-code-subagents-haiku-vs-sonnet-vs-opus-benchmarked)
  - In round 1, Opus scored 1.00 on all 23 task types and Sonnet averaged 0.98, but Opus's lead did not hold on repeats or across effort levels.
  - Final roster: 14 of 18 agents moved to Haiku 5.5 and 4 stayed on Sonnet 5.5. None needed Opus once agent definitions carried checklists and narrow tool lists. Higher effort helped mainly on translation.
  - Cost per run: Sonnet $0.125 to $0.147, Opus $0.274 to $0.327. Median time: Opus 38.5 s, Sonnet 19.6 s.
  - The study did not evaluate orchestrator or main-session models.
- Effort and reliability:
  - Mehta (arXiv, July 2026; 90 runs on one app-building task with Opus 4.7, historical): going from high to xhigh raised first-try perfect runs from 28% to 89%, at 9 to 29% more cost. Adding a browser testing tool raised cost 42 to 68% with no reliability gain — [agentpatterns.ai summary](https://agentpatterns.ai/patterns/agent-design/reasoning-effort-over-tool-scaffolding/)
  - A synthesis of tool-use and planning failures concludes that more agents, tools, reasoning effort or context does not uniformly improve reliability and can reduce it — [arXiv 2607.05775](https://arxiv.org/pdf/2607.05775)
  - A secondary report of an ICLR 2026 paper says reasoning-focused training increases hallucinated tool calls. The original paper was not checked — [Enterprise DNA](https://enterprisedna.co/resources/news/reasoning-trap-smarter-ai-agents-hallucinate-more-iclr-2026)
  - Xu & Wu (arXiv 2608.03169) is a preregistered study of low against max effort and unauthorized tool use, on GPT-5.6. Its results were not retrieved — [alphaXiv](https://www.alphaxiv.org/abs/2608.03169.md)

### Inferences
- The historical multi-agent result (token usage explains 80% of variance; a model upgrade beats doubling the budget) points in opposite directions for this question. More tokens, which is what higher effort buys, matter a lot, yet a stronger model beat simply spending more. Neither is direct evidence for Opus low against Sonnet high.
- The Sonnet 5.5 max FrontierCode regression and the 2025 "50 subagents" failure both show over-delegation as the orchestrator risk at high effort. Under-checking is the plausible risk at low effort, supported by the 28% to 89% first-try jump from high to xhigh in Mehta's single-task study.

### Gaps
- No benchmark or study tests the orchestrator seat specifically (dispatching, following long procedural instructions, tracking state across turns, avoiding busy-waiting) by model and effort level for the 5.5 family.
- No 5.5-generation per-effort instruction-following benchmark was found.

## Q5. Community reports comparing Opus low and Sonnet high in Claude Code for orchestration

### Takeaway
No concrete community report (Hacker News, Reddit or a blog with numbers) comparing Opus 5.5 at low effort against Sonnet 5.5 at high effort as a Claude Code orchestrator was found.

### Cited Findings
- The most common practitioner advice is Opus as the main or orchestrator model with Sonnet subagents, and Sonnet 5.5 for scoped fixes, specced features, tests, docs and subagent jobs — [Apidog](https://apidog.com/blog/claude-sonnet-5-5-claude-code/); [MyClaw](https://myclaw.ai/blog/sonnet-5-5-vs-opus-5-5)
- An illustrative cost model with Opus as orchestrator puts Sonnet subagents at $1,740 per month against $3,240 for Opus subagents. The source describes its numbers as illustrative — [Aleinikov](https://www.alekseialeinikov.com/en/blog/topics/ai/claude-haiku-5-5-vs-sonnet-5-5-vs-opus-5-5)

### Inferences
- The existing community default (Opus main thread) is usually run at Claude Code's default effort, which is medium, not low. So community experience does not speak to Opus at low effort as a controller.

### Gaps
- Hacker News and Reddit threads were not searched directly within the tool budget. A targeted search such as "opus 5.5 low effort claude code" restricted to those sites would settle whether such reports exist.
