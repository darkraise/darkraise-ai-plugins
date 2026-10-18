# Cost and usage-limit cost of a long Claude Code controller session: Sonnet 5.5 at high effort versus Opus 5.5 at low effort

Research date: 2026-10-18. All dollar figures are USD unless marked AUD.

## 1. API list prices for Opus 5.5 and Sonnet 5.5, and the Opus/Sonnet ratio

### Takeaway
Opus 5.5 costs exactly 2x Sonnet 5.5 on every price line: input, both cache-write tiers, cache read, output, and batch. Neither model has a long-context surcharge; the full 1M context is billed at the standard rate. Because the ratio is the same on every line, Opus-low costs less than Sonnet-high only if Sonnet-high uses more than twice the price-weighted tokens.

### Cited Findings
- Opus 5.5 list prices per million tokens (MTok): input $4, 5-minute cache write $5, 1-hour cache write $8, cache hits and refreshes $0.20, output $20 — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing) (fetched 2026-10-18)
- Sonnet 5.5 list prices per MTok: input $2, 5-minute cache write $2.50, 1-hour cache write $4, cache hits $0.10, output $10 — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- Cache hits on Opus 5.5 and Sonnet 5.5 are priced at 0.05x base input. Most other models pay 0.1x, and Fable 5.1 pays 0.025x. Cache writes cost 1.25x base input for the 5-minute cache and 2x for the 1-hour cache — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- Batch API: Opus 5.5 costs $2 input and $10 output per MTok; Sonnet 5.5 costs $1 and $5 — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- Long-context pricing: "Claude 4.6 and later models (except Claude Haiku 5.5) … include the full 1M token context window at standard pricing. (A 900k-token request is billed at the same per-token rate as a 9k-token request.)" — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- Opus 5.5 fast mode costs $8 input and $40 output per MTok. Fast mode is Opus-only — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- Compared with Opus 5, Opus 5.5 input and output are 20% cheaper and cache reads are 60% cheaper ($0.50 → $0.20) — [Addy Osmani, "What a task costs on Opus 5.5", Claude blog, 2026-09-25](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- "On Opus 5.5, an output token costs 100 times a cache read." ($20 / $0.20 = 100.) — [Claude blog, 2026-09-25](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- US-only inference (`inference_geo`) adds a 1.1x multiplier to every price category on both models — [Anthropic pricing page](https://platform.claude.com/docs/en/about-claude/pricing)
- The Aivy comparison says "Since 7 October the cache halves too", in a context that suggests a cache-price change after its 2026-09-28 readings — [Aivy](https://aivy.com.au/resources/claude-sonnet-5-5-vs-opus-5-5/). The Anthropic blog already gave Opus 5.5 cache reads at $0.20 on 2026-09-25 ([Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)), and the pricing page currently lists 0.05x. Unresolved: the source does not say what changed on 2026-10-07.

### Inferences
- Opus/Sonnet ratios: input 4/2 = 2.0; 5-minute write 5/2.50 = 2.0; 1-hour write 8/4 = 2.0; cache read 0.20/0.10 = 2.0; output 20/10 = 2.0. Any mix of token types therefore costs exactly twice as much on Opus. Opus-low is cheaper than Sonnet-high only when Sonnet-high's price-weighted token count is more than 2x Opus-low's.
- Neither model has a long-context tier, so a controller whose context grows past 200K pays no surcharge on either.

### Gaps
- The 2026-10-07 cache-price change mentioned by Aivy could not be confirmed from a primary source.

## 2. How effort changes token usage, and whether lower effort reduces tool calls

### Takeaway
Anthropic documents that effort scales all output tokens (thinking, text, and tool-call arguments) and that lower effort makes "fewer and terser tool calls". Anthropic publishes no percentage. Artificial Analysis measurements put Opus 5.5 low at about 30% of Opus 5.5 high's cost per task. On the same index, Opus-low costs about 51% of Sonnet-high per task and scores 4.4 points lower. These are single-request benchmark tasks, not long cached sessions.

### Cited Findings
- "The effort parameter affects **all tokens** in the response, including: Text responses and explanations; Tool calls and function arguments; Thinking (when active)… Lower effort also means fewer and terser tool calls." — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- With tools, lower effort tends to "Combine multiple operations into fewer tool calls; Make fewer tool calls; Proceed directly to action without preamble; Use terse confirmation messages". Higher effort "may make more tool calls, explain the plan before taking action, provide detailed summaries of changes" — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- "Effort is a behavioral signal, not a strict token budget. At lower effort levels, Claude still thinks on sufficiently difficult problems, but thinks less" — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- Opus 5.5 defaults to `medium`. Adaptive thinking is always on and cannot be disabled, so effort is "the primary control for how much the model reasons and what a request costs". Sonnet 5.5 defaults to `high` on the API, and its levels are "recalibrated" relative to Sonnet 5. For agentic coding, Anthropic recommends starting Sonnet 5.5 at `medium` "for well-specified tasks" and moving to `high` "for harder or longer ones". The docs describe `low` as suited to "Simpler tasks … such as subagents" — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- Sonnet 5.5 can run with `thinking: {"type": "between_tools"}`, its lowest thinking setting, at low, medium, and high effort. Opus 5.5 cannot disable thinking — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- Anthropic says Opus 5.5 "tends to think more per turn" than Opus 5 at the same effort, most of all at xhigh and max (Anthropic docs, as cited by) — [BuildThisNow, 2026-09-24](https://www.buildthisnow.com/blog/guide/mechanics/claude-opus-5-5-in-claude-code)
- "high adds 20K thinking tokens across a task. On Opus 5.5 that's $0.40." (Illustrative, not a measurement.) — [Claude blog, 2026-09-25](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Artificial Analysis Intelligence Index v4.3, read 2026-09-28, gives score and cost per task in AUD. Opus 5.5: low 42.3 / A$0.77; medium 51.2 / A$1.88; high 53.6 / A$2.56; xhigh 56.0 / A$4.86; max 57.6 / A$8.40. Sonnet 5.5: low 35.8 / A$0.58; medium 40.7 / A$0.82; high 46.7 / A$1.52; xhigh 51.9 / A$3.85; max 56.0 / A$10.67. Conversion rate: 1 AUD = 0.7123 USD — [Aivy, citing Artificial Analysis](https://aivy.com.au/resources/claude-sonnet-5-5-vs-opus-5-5/)
- The USD equivalents match other reports: Opus 5.5 low ≈ $0.55, medium ≈ $1.34, max ≈ $5.98 ([eesel review](https://www.eesel.ai/de/blog/claude-opus-5-5-review)). Sonnet 5.5 max is $7.60 per task, and Sonnet 5.5 at max averaged about 193K output tokens per task, "around 60% higher than Opus 5.5 (max)" ([AI Weekly](https://aiweekly.co/alerts/claude-sonnet-55-ranks-2-at-56-with-record-token-burn); [OODA Loop](https://oodaloop.com/briefs/technology/claude-sonnet-5-5-reaches-2-on-artificial-analysis-index-but-uses-more-tokens/)). Artificial Analysis tested a pre-release Sonnet build with a structured-outputs bug — [AI Weekly](https://aiweekly.co/alerts/claude-sonnet-55-ranks-2-at-56-with-record-token-burn)
- In a single-run Claude Code `/goal` build (Nate Herk video, page updated 2026-09-24), Opus 5.5 recorded: low 191K tokens, $3.91 API-equivalent, 16m43s; medium 419K, $12.44; high ~559K, $16.31; xhigh ~732K, $25.92; max 1.18M, $50.38. Caveats: one task, no subagents, some token figures read from garbled captions, and tool calls not reported — [OpenClaw Database](https://openclawdatabase.com/news/videos/2026-09-24-opus-55-every-effort-level-cost-comparison/index.md)
- One tester found Sonnet 5.5 at the API default of high "used nearly twice the tokens of medium without better output". This comes from a search summary of [Aivy](https://aivy.com.au/resources/claude-sonnet-5-5-vs-opus-5-5/) or [The New Stack](https://thenewstack.io/claude-sonnet-5-5-vs-opus-5-5/), but the fetched Aivy page does not contain the claim and the New Stack body could not be retrieved. Unverified.

### Inferences
- USD per task, computed as AUD × 0.7123: Opus low 0.77 × 0.7123 = $0.548; Opus high 2.56 × 0.7123 = $1.823; Sonnet high 1.52 × 0.7123 = $1.083.
- Effect of effort on Opus 5.5 cost: low/high = 0.548 / 1.823 = 0.30 on the Artificial Analysis index, so low is about 70% cheaper. The Herk run gives a similar picture: 191K / 559K = 0.34 of the tokens and $3.91 / $16.31 = 0.24 of the cost.
- Opus-low versus Sonnet-high on the Artificial Analysis index: cost ratio 0.548 / 1.083 = 0.51, so Opus-low costs about half as much per task, and it scores 42.3 against 46.7. Since unit prices differ by 2x, Sonnet-high used about 2 × 1.083 / 0.548 ≈ 3.95x the price-weighted tokens of Opus-low on these tasks.
- On Sonnet 5.5, the high/medium cost ratio is 1.52 / 0.82 = 1.85, and high/low is 1.52 / 0.58 = 2.62.
- Artificial Analysis tasks are dominated by output and carry little cache, so the 0.51 ratio overstates Opus-low's advantage for a controller session dominated by cache reads. Section 3 covers that case.

### Gaps
- No Anthropic figure such as "low uses X% fewer tokens than high" was found for either model.
- No measurement of tool-call counts by effort level for Opus 5.5 or Sonnet 5.5 was found. The Herk run counted "checks" per effort level (22 at low and 22 at high, rising to 51 at max), but these are not tool calls.
- Output tokens per task by effort level (excluding max) were not found for either model.

## 3. Cache reads versus output in a long controller session, and whether effort affects the cache-read share

### Takeaway
Effort changes only how much each turn outputs. Cached input is re-read every turn at a price fixed by the model, so Opus pays exactly 2x for the same context no matter what effort it runs at. Effort reaches the cache-read bill only indirectly: fewer tool calls mean fewer turns, and shorter outputs mean slower context growth. In a long session dominated by cache reads, Opus-low's cost advantage shrinks from the roughly 0.5x per-task ratio above toward, or past, parity. It stays cheaper only if Sonnet-high produces several times more output per turn or takes many more turns.

### Cited Findings
- Anthropic's worked "typical task" uses 2.0M cache-read tokens, 200K fresh input, and 60K output. At Opus 5 prices this is $1.00 (29%), $1.00 (29%), and $1.50 (43%), for a total of $3.50. The same session costs "about 31% less" on Opus 5.5, about $2.40 — [Claude blog, 2026-09-25](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- "The 60K output tokens of a typical task cost $1.20, the same as reading 6M tokens from cache." — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Per-turn cache read on Opus 5.5 costs "about $0.004" at 20K context and "about $0.03" at 150K. "30 turns at that size spend $0.90 on reads alone." — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- At 40 turns with context growing from 20K to 120K (about 70K average), a session reads "about 2.8M input tokens", or $1.62 at a 90% cache hit rate and about $0.99 at 96%. With no cache it costs $11.20 — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Cache writes at 120K context on Opus 5.5: a 5-minute write costs "about $0.60" and a read "about $0.02", so "One write costs as much as 25 reads". A 1-hour write costs about $0.96. Compacting at 150K costs about $0.25 and pays for itself in about ten turns — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- In Claude Code, the cache lifetime is "one hour on a subscription; five minutes on an API key or cloud provider". A subscription "drops to five minutes once it's drawing on usage credits" — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Changing top-level effort between requests invalidates the prompt cache. Opus 5.5 and Sonnet 5.5 both support per-message effort changes (beta header `mid-conversation-output-config-2026-07-01`), which preserve the cache — [Anthropic effort docs](https://platform.claude.com/docs/en/build-with-claude/effort)
- Agent teams use "about seven times the tokens of a standard session when teammates run in plan mode" — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)

### Inferences
- Shares of Anthropic's typical task at Opus 5.5 prices, recomputed: cache reads 2.0M × $0.20 = $0.40 (17%); fresh input 0.2M × $4 = $0.80 (33%); output 0.06M × $20 = $1.20 (50%); total $2.40. Even this short task spends half its cost on input-side tokens, and effort has no direct effect on them.
- Illustrative controller model. The inputs are assumptions, not measurements: 150 turns, 100K average cached context, 4K newly cached tokens per turn at the 5-minute write rate, and 1.5K output tokens per turn for Opus-low.
  - Cache reads: 150 × 100K = 15M tokens. Opus 15 × $0.20 = $3.00; Sonnet 15 × $0.10 = $1.50.
  - Cache writes: 150 × 4K = 0.6M tokens. Opus 0.6 × $5 = $3.00; Sonnet 0.6 × $2.50 = $1.50.
  - Opus-low output: 150 × 1.5K = 0.225M × $20 = $4.50. Opus-low total = $10.50, of which 57% is input-side ($6.00 / $10.50).
  - Sonnet-high break-even: $10.50 − $3.00 input-side = $7.50 of output, which buys 0.75M tokens at $10 per MTok, or 5K per turn. That is 3.3x Opus-low's output per turn at the same turn count and context.
  - Per turn at 150K context with a 4K write: Opus pays 0.15 × $0.20 + 0.004 × $5 = $0.050 before any output; Sonnet pays $0.025. Sonnet-high therefore has $0.025 per turn, or 2.5K output tokens, of headroom before output differences even begin to count.
- What effort does to the cache-read share: if Opus-low makes fewer tool calls, the session has fewer turns and fewer cache reads. Shorter outputs and tool results also slow context growth, which every later turn re-reads. These indirect savings are real, but no source quantifies them for a controller workload.
- A dforge-like controller holds a large context for many turns and mostly dispatches work rather than reasoning at length. On that profile Opus-low may cost about the same as Sonnet-high, or more. Whether it does depends on Sonnet-high's output per turn, which was not measured for this workload.
- For the owner's case, measured numbers would settle the question: per-turn `cache_read_input_tokens`, `cache_creation_input_tokens`, and `output_tokens` from real dforge controller transcripts under both configurations. The repo's `session-report` skill reads these from `~/.claude/projects` transcripts.

### Gaps
- No published breakdown of cache reads versus output for a long multi-hour orchestrator session on Opus 5.5 or Sonnet 5.5 was found.
- No measurement of how effort changes turn count or context growth in a long session was found.
- Whether subscription accounting prices Claude Code's 1-hour cache writes at the 1-hour API rate (2x input) was not found.

## 4. Claude Code subscription usage limits as of October 2026: model weighting, separate caps, and effort

### Takeaway
Max has a 5-hour session limit, one weekly limit shared across all models, and a separate weekly limit for Fable. The current help article mentions no Opus-only or Sonnet-only weekly cap. Anthropic does not publish token sizes for the limits or explicit model weights. Its Opus 5.5 blog does say the price cut "is passed on to your limits, including cached context". That implies limit consumption tracks API-equivalent cost, so an Opus token burns about 2x a Sonnet token, and effort matters only through the tokens it produces.

### Cited Findings
- Pro and Max plans have a five-hour session limit plus a weekly limit. The general weekly limit is "shared between Claude and Claude Code". "Max plans also have a separate weekly limit for Fable." The article mentions no Sonnet-only or Opus-specific limit. When usage credits are enabled, a Max user can keep working past the 5-hour, weekly, or Fable weekly limit. Remaining allocation is shown via `/status`. (Article marked "Updated this week", fetched 2026-10-18.) — [Anthropic Help Center, "Using Claude Code with your Pro or Max plan"](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- "On a Pro, Max or Team plan, the lower Opus 5.5 price is passed on to your limits, including cached context, so they go about 25% further than on Opus 5." — [Claude blog, 2026-09-25](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Weekly limits have been "25% higher than they were before the promotion" since 2026-09-14 for Pro, Max, Team, and seat-based Enterprise. A promotion that made Claude Code weekly limits 50% higher ran from 2026-05-13 through 2026-09-13. "5-hour usage limits were not affected by this promotion." — [Anthropic Help Center, article 15910845, dated 2026-09-14](https://support.claude.com/en/articles/15910845)
- At the Opus 5.5 launch, five-hour limits "went up on Pro, Max, Team and seat-based Enterprise plans" with no figure given — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/). MakeUseOf reports the increase at about 20%, but Anthropic gave no percentage. Notebookcheck reports one banked rate-limit reset per subscriber, shown in the app as expiring 2026-10-22 — both as relayed by [BuildThisNow, 2026-09-24](https://www.buildthisnow.com/blog/guide/mechanics/claude-opus-5-5-in-claude-code)
- "Anthropic does not publish how many tokens a Pro or Max window holds." — [BuildThisNow](https://www.buildthisnow.com/blog/guide/mechanics/claude-opus-5-5-in-claude-code)
- Since Claude Code 2.1.280 (2026-09-22), the `default` model setting resolves to Opus 5.5 on Pro, Max, Team, Enterprise, and the Anthropic API — [BuildThisNow, citing Claude Code model-config docs](https://www.buildthisnow.com/blog/guide/mechanics/claude-opus-5-5-in-claude-code)
- Historical (Opus 4 era): an Anthropic support article said Opus reaches usage limits "approximately five times faster than Sonnet" — reported in a search summary of [support.anthropic.com article 11145838](https://support.anthropic.com/en/articles/11145838). The current version of that article no longer contains the statement, and it predates the Opus 5.5 pricing, under which Opus costs 2x Sonnet.
- Historical or unverified: third-party guides describe two weekly bars on Max, "Current week (all models)" and "Current week (Sonnet only)", and some describe a separate Opus weekly allowance — [ClaudeLog](https://claudelog.com/faqs/claude-code-usage-limits/); [UsageBar](https://usagebar.com/blog/claude-pro-vs-max-limits); [SmartScope](https://smartscope.blog/en/blog/claude-opus-5-5-weekly-limit-max-plan-2026/). The current official article lists only the all-models weekly limit and the Fable weekly limit.

### Inferences
- If limits are priced like the API, which the "passed on to your limits, including cached context" statement implies, then one Opus 5.5 controller turn burns exactly 2x the limit of the same Sonnet 5.5 turn. The section 3 arithmetic then carries over to limit burn: Opus-low's limit advantage over Sonnet-high exists only when Sonnet-high's extra output and extra turns outweigh the doubled input-side cost.
- Opus and Sonnet now share the same weekly pool, and Fable alone has its own cap. Moving the controller from Opus to Sonnet therefore does not open a separate allowance; it only halves the per-token draw on the shared pool.
- Effort affects limit consumption only through the output tokens, turn count, and context growth it causes. Nothing found suggests effort has its own weight in limit accounting.

### Gaps
- No official number was found for limit size in tokens, for model weights, or for the exact Max 5x and 20x weekly allowances.
- Whether an Opus-only weekly cap exists today is not confirmed. The official article omits one, which suggests none exists, but it does not explicitly deny one.
- Whether cache writes and cache reads count toward limits at exactly their API price ratios is implied by the blog but not stated in a help-center article.

## 5. Published guidance or community measurements comparing Opus-low and Sonnet-high session cost or limit burn in Claude Code

### Takeaway
No direct measurement of Opus 5.5 low against Sonnet 5.5 high in a long Claude Code session, in dollars or in limit percentage, was found. The closest data is the Artificial Analysis per-task index: Opus-low costs about 0.51x Sonnet-high and scores lower (42.3 against 46.7). Community reports on limit burn are anecdotal and conflicting.

### Cited Findings
- Artificial Analysis: Opus 5.5 low scores 42.3 at A$0.77 per task, and Sonnet 5.5 high scores 46.7 at A$1.52. At every effort level from low to xhigh, Opus 5.5 scores 4.1 to 10.5 points above Sonnet 5.5 at the same level — [Aivy, citing Artificial Analysis v4.3, read 2026-09-28](https://aivy.com.au/resources/claude-sonnet-5-5-vs-opus-5-5/)
- At matched score, Opus 5.5 xhigh and Sonnet 5.5 max both score 56.0, at $3.46 and $7.60 per task — [Aivy](https://aivy.com.au/resources/claude-sonnet-5-5-vs-opus-5-5/) (A$4.86 and A$10.67 converted at 0.7123); [AI Weekly](https://aiweekly.co/alerts/claude-sonnet-55-ranks-2-at-56-with-record-token-burn)
- The New Stack's comparison is headlined "Claude Sonnet 5.5 vs. Opus 5.5: 42% cheaper and perfect on every run" (Jessica Wachtel, 2026-10-08). The article body, including what "42% cheaper" measures and at which effort levels, could not be retrieved — [The New Stack](https://thenewstack.io/claude-sonnet-5-5-vs-opus-5-5/)
- Migrating a 44-ticket support benchmark from Opus 4.8 to Opus 5.5 at low effort "cut the benchmark's cost by about 18%" — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Enterprise Claude Code spend averages "about $13 per developer per active day", and "For 90% of users, cost stays below $30 per active day" — [Claude blog](https://claude.dev/blog/what-a-task-costs-on-opus-5-5/)
- Anecdotal and conflicting limit-burn reports: some users say Opus 5.5 is near-unlimited on the $200 plan, while others say the weekly limit runs out quickly — [SmartScope](https://smartscope.blog/en/blog/claude-opus-5-5-weekly-limit-max-plan-2026/); [Drea Says substack](https://dreasays.substack.com/p/claude-55-is-brilliant-confusing) (search-summary level, not fetched)

### Inferences
- The Artificial Analysis 0.51x ratio is a lower bound on Opus-low's relative cost for a controller. Benchmark tasks are short and heavy on output, while a controller's cost is weighted toward cached input, where the ratio is a fixed 2.0x. The true controller ratio lies between 0.51x and 2.0x. Where it falls depends on the share of input-side cost and on how much more output and how many more turns Sonnet-high produces. Section 3's illustrative model puts parity at Sonnet-high outputting about 3.3x Opus-low's tokens per turn.
- On quality, Opus-low scores below Sonnet-high on the general index (42.3 against 46.7), so Opus-low is not a strict upgrade. Whether controller work, which is dispatching, ledger-keeping, and review routing, needs that reasoning depth was not covered by any source found.

### Gaps
- No Claude Code transcript-level or `/usage`-percentage comparison of the two configurations on any long orchestrator workload was found.
- The New Stack article body was not retrieved.
- A local A/B test of dforge controller transcripts would settle the question: sum cache-read, cache-write, and output tokens per turn, then weight them by the 2:1 price ratio.
