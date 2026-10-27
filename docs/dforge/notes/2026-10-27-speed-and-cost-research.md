# Speed and cost research for subagent-driven development — 2026-10-27

Sources: Anthropic's "when to fold subagents into your main agent loop" and 21 related
Anthropic pages, 22 external sources, and the Claude transcripts of 56 dforge sessions
(2026-09-27 to 2026-10-27). Dollar figures are list API prices applied to measured tokens.

## Open questions

1. Can a subagent's prompt-cache TTL be raised? Answered below.
2. Should the single-agent-loop pattern replace dforge's subagent mode? Answered below.
3. Which further changes would make dforge more accurate, faster and cheaper? Ranked below.
4. What do other Claude Code workflow plugins and skills do for speed and cost, and does
   Anthropic's guidance favour one general agent over per-kind agents on Opus 5.5 / Sonnet 5.5?
   Answered in section 4.

## 1. Subagent cache TTL

- Plugin agents support `experimental.cacheTtl` and `omitClaudeMd` (Claude Code plugin
  components docs). The settings key `subagentPromptCacheTtl` cannot ship in a plugin: plugin
  settings honour only `agent` and `subagentStatusLine`. A `1h` value is ignored while a
  subscription draws usage credits.
- Verified on Claude Code 2.1.311: a plugin agent with `cacheTtl: 1h` wrote
  `ephemeral_1h_input_tokens` and no 5-minute writes. Today every dforge subagent writes 5m.
- Not worth enabling across the board. Judges never idle past 5 minutes, so `1h` only doubles
  their write price (about +$203 over the window). Implementers would save about $49 of
  mid-run misses and about $20 of fix rounds sent fresh for cache reasons (45 of 237 round-1
  fixes), against about $118 of dearer writes.
- 58 of 98 implementer cache misses followed a wait on a long full-suite run (suite-run,
  test-all, until/sleep polls, Monitor); 20 followed a fix-round resume.
- `omitClaudeMd` saves about 2.4k tokens per dispatch here but strips the project notes a
  judge reviews against; not recommended.

## 2. Single agent loop

dforge already runs inline by default and enters subagent mode only for heavy plans. Earlier
measurements: a subagent-mode controller grows about half the context per task of an inline
one (9.7k vs 19.1k). dforge splits by task with file handoffs, the "split by context" pattern
the article endorses. Its controller runs Sonnet 5.5 high (decision of 2026-10-18).

Where the overhead sits:

- dforge judges cost $782 against $822 for implementers.
- On judge-opus, 202 rulings cost $188, above 289 task reviews at $168.
- `cannot-verify` is the largest ruling kind: 100 rulings, still 43 on 2026-10-27 after
  register row 4 (token-efficiency) moved them to judge-sonnet-high. The items are mostly
  mechanical facts the identity and attribution checks do not cover: a test failing at the
  base commit, a symbol or test existing, git history.

Adopt from the article: merge consecutive tasks that chain on each other's output into one
implementer dispatch; precompute mechanical facts in the review package; measure each change
on isolated replays.

## 3. Ranked changes

1. Evidence-bound findings: each judge finding cites a failing command or a quoted brief line,
   and a fix round starts only for findings that reproduce; add "skip style" to the reviewer
   prompt. (arXiv 2603.00539: explain-and-fix prompting raised GPT-4o false negatives on MBPP
   from 184 to 451; a fix-guided filter cut average false negatives from 54.8% to 16.3%.)
2. Extend task-step's mechanical checks to baseline test status at the base commit and
   symbol or test existence, so those cannot-verify items reach no seat.
3. Diff-first, narrow judge search (GitHub Copilot review: about 20% lower cost, vendor figure).
   Judges currently write a median of about 57k tokens of cold-start cache.
4. Implementers run targeted tests; the controller runs the full suite once through suite-run.
5. Implementer prompt: add the anti-hardcoding, report-incorrect-tests and tests-are-immutable
   clauses (none present today). The real-check clause and the no-subagent rule already exist.
6. Brief as contract: machine-readable done-list and acceptance commands; the judge checks the
   stated objective (MAST arXiv 2503.13657: +15.6%, the largest intervention; R2E-Gym: tests plus
   model review 51% vs 42-43% for either alone).
7. Re-tune the score-to-effort table with a sweep (Opus 5.5 medium matches Opus 5 high on coding;
   Sonnet 5.5 medium for well-specified agentic coding).
8. Parallel waves of 3-5 workers with disjoint files and shared decisions in the header; stagger
   same-type dispatches a few seconds so later ones read the first one's cache.
9. An isolated replay eval of 20-50 tasks from real dforge failures, reporting pass^k; the
   prerequisite for 1, 6, 7 and 10.
10. Pilot only: trajectory-based escalation (SWE-Router, 100-task workshop paper) and no judge
    for score 0-2 tasks.

Rejected: a `hooks` field in implementer frontmatter (plugin agents ignore it; see section 4
for the plugin-level `SubagentStop` route); a blanket 1h subagent TTL.
Already present: final-review union with per-finding verification.

Prompt clauses today: every Sonnet implementer tier has the scope-limit clause, the Opus tiers
do not; only impl-sonnet-low has the real-check clause; no tier has anti-hardcoding,
report-incorrect-tests or tests-are-immutable.

## 4. Other plugins, official features, and the general-agent claim

General agent versus per-kind agents. The closest official statements are the commerce-agents
article (2026-09-02: "a single agent with skills consistently has outperformed both the
one-prompt-for-everything design and the subagent design", in tightly coupled sessions) and the
single-agent-loop kit ("does not assume a single loop always wins. It measures"; keep subagents
for parallel fresh-context work, independent verification, and work that reads far more than
the main agent needs afterwards). No official statement tied to Opus 5.5 or Sonnet 5.5 was
found. dforge's agents are one implementer role and one judge role at several model and effort
tiers, not per-kind specialists, so the claim argues against adding persona or lens reviewers
(register row 15) and for widening inline mode once an eval shows it holds quality; it does not
argue against the independent judge.

New items, ranked:

1. Plugin `SubagentStop` gate: hooks docs say the input carries `agent_type` and
   `agent_transcript_path`, and exit 2 keeps the subagent running with the reason as its next
   instruction. Block an implementer stop whose report lacks the required sections or a passing
   verified command. Needs Claude Code 2.1.311+ (earlier versions double-fire); whether the
   8-block cap applies is unverified.
2. Split SKILL.md files over ~20 KB and add a size test. After compaction each invoked skill
   keeps only its first 5,000 tokens (25,000 shared). Six dforge skills exceed 20 KB
   (subagent-driven-development 49 KB, brainstorming 42 KB, executing-plans 36 KB, writing-plans
   35 KB, finishing 29 KB, writing-skills 26 KB); only the ui-ux test checks size. Upstream
   superpowers 7.0.1 lost its fix-round cap this way (18 rounds) and now caps at 20,000 bytes.
3. Lean plans: decisions, signatures and test assertions instead of full code. Superpowers
   6.4.2 measured a quarter of the planning time and a third of the tokens with 9/9 planted
   defects still caught (one reproduction). Overlaps register row 14 (deferred).
4. Implementers background slow suites and wait for the completion notification instead of
   polling (Claude Code 2.1.300 fixed model polling of background commands); pairs with section 3
   item 4.
5. `/doctor prompt-audit` over skills, agents and references (Anthropic reports a further 9%
   cost cut in a model migration), then `/skill-doctor` for listing cost, and
   `disable-model-invocation: true` on skills only ever invoked by name.
6. Review gating by diff size and risk, with a cheap pre-check (Anthropic's code-review plugin
   gates eligibility on Haiku and keeps findings scored >= 80).
7. Auto mode for unattended waves (server-side classifier, no classifier token charge on the
   Claude API) and `worktree.baseRef: "head"` as a user setting for wave worktrees.
8. Measure with `claude plugin eval` (`--runs`, `-j`, `--max-cost-usd`, `costUsd` and
   `durationSeconds` per case) alongside the existing tier evals.

Low value or rejected: fast mode (Opus only, about 2x price for up to 2.5x speed, subagent use
unknown, controller is Sonnet); per-spawn `effort` to collapse tiers (saves about 1k listing
tokens, loses the pinned-tier guarantee); `/goal`; ultracode during execution; generic output
compression skills (JetBrains measured rtk at +7.6% cost, Ponytail at -10.3% against a -20%
claim); context-mode and claude-mem (dforge already hands artifacts over as files).
