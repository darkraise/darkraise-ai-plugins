# dr-superpowers 1.0 — standalone superpowers fork (program design)

Date: 2026-09-11. Status: approved direction; program-level design. Each sub-project in
§6 gets its own spec and plan, written in a fresh session.

Reviewed by an independent Fable pass on 2026-09-11 (verdict: needs rework); every finding
is resolved in §5 or §6.

## 1. Goal

Turn `plugins/dr-superpowers` from an extension of `superpowers@claude-plugins-official`
6.3.0 into a standalone, curated fork that:

1. Drops the upstream dependency and the workaround layer it forces. Today
   `dispatching-tiered-implementers` is 731 lines, much of it rules for not breaking upstream's
   ledger and crash recovery, plus arguments for three superseded upstream instructions.
2. Bakes in the Karpathy guidelines (forrestchang/andrej-karpathy-skills, MIT) where they fire.
3. Cuts subscription usage while keeping quality.
4. Lets a strong model plan and small models (Sonnet 5, Haiku 4.5) execute plans literally.

Decisions already made by the owner:
- Claude Code and Codex hosts only.
- One small Claude SessionStart hook; the PreToolUse hook is deleted.
- Frozen at upstream 6.3.0, with no ongoing upstream sync.
- The plan decides its execution mode.

## 2. Evidence (transcripts, 24h before 2026-09-11)

- **Where tokens went.** Main-session Opus 5 used ~505M raw tokens (~92%); all subagents ~7%;
  judges 0.7M.
- **Context size.** 1,190 of 1,345 main requests ran above 150k context. Two sessions peaked at
  689k/680k with no compaction, because Fable and Opus 5 run a native 1M window and compact only
  at ~967K by default.
- **What those sessions did.** Brainstorm → plan → inline execution → a long interactive tail,
  all in one session. In the largest (195M) session, about 60M was execution and about 130M was
  the tail at 500–690k.
- **Fixed baseline.** ~58k tokens per request: system prompt, tools, CLAUDE.md, skill and agent
  lists.
- **Context growth per main request.** Median 0.9k, mean 1.8k. Growth comes from many small turns
  (Bash about 0.8k each) plus retained thinking.
- **One oversized implementer.** An `impl-opus-high` implementer reached 381k context during a
  long fix loop.

## 3. Cost model (subscription)

Anthropic does not publish how subscription limits weight tokens, so the exact weighting is
Unknown. Two facts anchor the model:

- Claude Code's own usage insight says long context is "more expensive even when cached".
- Its per-session `cost-state` records reproduce API pricing exactly. For example, session
  de6e2de8 records $112.47 for Opus 5, matching reads at 0.1×, one-hour cache writes at 2× and
  output at 5× of a $5/M base.

This design assumes limits roughly track that API-equivalent cost. Label: inference.

**Weights**, in units of the model's base input price:

| Token kind | Weight |
|---|---|
| Uncached input | 1 |
| Cache read | 0.1 |
| Cache write, 5-minute cache (subagents) | 1.25 |
| Cache write, 1-hour cache (main sessions) | 2 |
| Output, including thinking | 5 |

The transcripts confirm the cache split: main sessions write `ephemeral_1h`, subagents write
`ephemeral_5m`.

**Measured weighted split:**
- Main sessions: reads 79%, cache writes 11%, output 10%.
- Subagents: reads 46%, writes 39%, output 15%. Subagents are about 15% of weighted cost, not the
  7% raw figure, because every fresh subagent pays cache writes and output at full weight.

**Relative model cost**, implied by 14 days of cost records: Haiku 4.5 ≈ 1, Sonnet 5 ≈ 2,
Opus 5 ≈ 5, Fable 5 ≈ 10, Fable 5.1 ≈ 6–7 (mixed records). Execution on Sonnet instead of Opus
is therefore about 2.5× cheaper per token.

**Optimal clear point.** Take a session segment of `n` requests that starts at reload size
`B + R` (baseline plus handoff reload) and grows by `g` per request. Its cost is about
`w·(B+R) + r·(n·(B+R) + g·n²/2)`, where `w` is the one-time cache-write weight and `r` the read
weight. The per-request cost is minimised at `n* = sqrt(2·w·(B+R) / (r·g))`.

With B+R ≈ 83k, g ≈ 1.8k, w = 2 and r = 0.1, that gives n* ≈ 43 requests, a clear point near
**160k context**. The optimum is flat, so 150–200k performs almost identically. Clearing at that
point cuts read-plus-write cost roughly 2.5–3× against sessions that average about 430k.
Sensitivity: if subscription limits weighted reads higher, the optimum moves lower, never higher.

**Owner ruling 2026-09-11: the working budget is 475k, not the cost optimum.** 200–250k proved
too low in practice — handoffs came too often, and the reload overhead plus continuity loss
outweighed the read savings. The math above stays as the cost reference; the 475k budget
knowingly trades higher read cost for longer uninterrupted phases.

**Cache expiry.**
- *Main sessions (1-hour cache).* Continuing a large session after more than an hour idle
  re-writes the whole context at 2×; a 600k session costs about 1.2M-equivalent in one request.
  Hand off before breaks.
- *Subagents (5-minute cache).* Resuming an implementer after a review that took over 5 minutes
  re-writes its whole context at 1.25×. We observed 10 such cold re-writes, 6.9% of subagent cost,
  some after 9-minute gaps. See rule R4 in §5.

**Codex.** The Codex executor lane runs on a separate ChatGPT subscription, so offloaded tasks
leave the Claude budget entirely. The existing lane (score 2–4, risk ≤1) stays.

**Settings change applied 2026-09-11, outside the plugin.** `"autoCompactWindow": 500000` in
`~/.claude/settings.json` (initially 200000; raised the same day with the 475k ruling above).
The setting is documented at
code.claude.com/docs/en/model-config (range 100K–1M). It is the backstop; the plugin's clean
handoff budget of 475k (§5) fires first. Dropping `[1m]` would change nothing, because Fable and
Sonnet 5 run a native 1M window on Max plans.

## 4. Target shape

```
plugins/dr-superpowers/            1.0.0 (breaking)
  .claude-plugin/plugin.json       no superpowers dependency
  .codex-plugin/plugin.json        "hooks": {}
  hooks/hooks.json                 SessionStart only: startup|resume|clear|compact
  scripts/session-start.sh         injects compact entry point; persists transcript_path
  scripts/                         Codex-lane scripts + sdd-workspace, task-brief,
                                   review-package, context-size, repo-audit, plan-lint
  skills/ (15)                     using-superpowers, brainstorming, selecting-approaches,
                                   writing-plans, executing-plans, subagent-driven-development,
                                   handoff, resume-execution, test-driven-development,
                                   systematic-debugging, verification-before-completion,
                                   requesting-code-review, receiving-code-review,
                                   finishing-a-development-branch, using-git-worktrees,
                                   writing-skills
  skills/<name>/references/        single-skill material (progressive disclosure)
  reference/                       ladder.md, native-codex.md, codex-routing.json,
                                   external-task-recovery.md, external-executor.md,
                                   session-budget.md
  criteria/                        task-review.md (+scope), approach-selection.md,
                                   plan-review.md, codex-review-schema.json, TEMPLATE.md
  agents/ (19)                     preload dr-superpowers:verification-before-completion
  LICENSES/                        superpowers (Jesse Vincent, MIT); karpathy-skills (MIT)
```

Dropped from upstream:
- `dispatching-parallel-agents`, because the Agent tool and Codex spawn docs cover it.
- The brainstorming visual companion, a 26KB server; the Artifact tool covers visuals on Claude.
- Adapters for the other six hosts, plus upstream docs, release notes and tests for dropped parts.

Skill names stay identical to upstream under `dr-superpowers:`.

## 5. Cross-cutting rules (resolve the review findings)

- **R1. One ledger grammar for both modes.**
  - Every task gets its own `Task <N>: complete ...` line, even inside a reviewed group.
  - Group reviews log as `Group <a>-<b>: review round R/<cap>`.
  - Per-task checkpoints go on the complete line: Done / Verified / Remaining, Discovered issues,
    Assumptions.
  - Mode switches happen only at a task boundary where every earlier task is complete.
- **R2. The plan is immutable during execution.**
  - The plan-amender writes `<workspace>/amendments.md` (task, old text, new text, reason) and a
    ledger `Ruling:` that cites it.
  - `task-brief` applies amendments when it extracts a task, and `plan-lint` re-checks each
    amended task.
- **R3. Small executors do not own judgment.**
  - Sonnet controllers rule only on mechanical conflicts.
  - These go to a strong judge, which returns CONFIRMED-GAP or PARK with a ruling: the
    pre-flight conflict scan, breaker adjudication at the cap, "cannot verify from diff" items,
    and final-review dedupe.
  - Design-level plan defects go to the plan-amender (R2).
- **R4. Resume or re-dispatch by cache state.**
  - Resume an implementer for a fix round only when its last activity was under 5 minutes ago or
    its context is under ~100k.
  - Otherwise dispatch a fresh implementer on the same tier with the brief, the report file and
    the findings.
  - Never use `fork` implementers. Codex already uses `fork_turns: none`.
- **R5. Inline eligibility.** Inline mode only when every task scores 3 or less on the Claude
  rubric (the Sonnet band) and no task is risk 3. Otherwise subagent mode.
- **R6. Execution line.** `**Execution:** <inline|subagent> — claude --model <m> --effort <e> —
  <reason>`. The flag syntax is verified in the docs. Codex plans state the native pair per
  native-codex.md; judges, plan review and the amender are at least Astra high.
- **R7. Budget.**
  - Clean handoff at 475k by `scripts/context-size`, which reads the `transcript_path` the
    SessionStart hook persisted. No dependency on the undocumented `CLAUDE_CODE_SESSION_ID`.
    (Owner ruling in §3: 475k overrides the 160k cost optimum.)
  - Codex: hand off every 3 tasks, or after any task that needed 3 or more fix rounds.
  - Phase boundaries are hard stops: plan saved and reviewed, execution done, final review done.
  - Also hand off before a break of more than an hour.
  - Brainstorm and spec phases hand off with the draft path as their authority.
- **R8. Handoff locations.**
  - `latest.md` always lives at `<primary-repo>/.superpowers/handoff/latest.md` and carries the
    absolute worktree path, the workspace handoff path and the next-session command.
  - The execution handoff is `<worktree>/.superpowers/sdd/<plan>/handoff.md`.
  - `resume-execution` verifies the worktree's HEAD via `git worktree list`.
  - Plan and spec are committed before the plan-saved stop.
  - **Every handoff ends with a resume guide printed to the owner** (owner request
    2026-09-11): the exact launch command (`claude --model <m> --effort <e>` from the
    Execution line, or the phase's model), the directory to launch it in, and a
    copy-pasteable resume prompt naming the handoff file and the next step. The `handoff`
    skill owns printing it; `latest.md` carries the same block under `## Next session`, so
    the guide survives even when the printing session is gone.
- **R9. Plans stay single files.** Folder plans are dropped: they collide in `sdd-workspace`
  naming, and `task-brief` already gives one-task reads. The plan gains a header block
  (Execution line, Global Constraints, Contracts, Assumptions with evidence, task index), and the
  controller reads only that header plus one extracted task at a time. Execution sessions never
  read the spec; only plan review, the amender and the final review do.
- **R10. Criteria.**
  - `{#spec}` owns features and requirements; `{#scope}` owns hygiene: style drift, comment
    edits, adjacent refactors, deleted pre-existing dead code, orphans.
  - The four-score Codex review schema ships as `criteria/codex-review-schema.json`.
  - Plan review adapts upstream's `writing-plans/plan-document-reviewer-prompt.md` into
    `criteria/plan-review.md`, scoring executability, coherence, coverage, and assumptions with
    evidence.
- **R11. One checker.** `plan-lint` absorbs `assigning-implementers`' "Check your work" checks.
- **R12. Karpathy placement.** A ≤1.2k-token entry point carries a routing table ("invoke when
  the task matches"), the four principles (with "ask" limited to design phases), the owner's
  process-depth rules, and the budget and compaction-recovery rules. Two-to-three-line
  reinforcement blocks go in writing-plans, executing-plans, the implementer template and TDD.
  Also adopted:
  - the test quality bar ("passes with `return <constant>` = invalid");
  - loop-breaker red flags;
  - walking skeleton for greenfield systems;
  - prefer an indexed code tool (for example darkmem `code_search`) over Explore subagents;
  - implementer reports gain Discovered issues (not fixed) and Assumptions made.

## 6. Decomposition (each its own spec + plan, in order)

1. **Standalone base.**
   - Copy the kept upstream skills with names and wording fixed; drop hosts and the visual
     companion.
   - SessionStart hook with matchers `startup|resume|clear|compact`; entry-point injection;
     `LICENSES/`.
   - Manifests at 1.0.0 on both clients, no dependency, remove
     `allowCrossMarketplaceDependenciesOn`.
   - Agent preloads renamed.
   - Validator and tests:
     - replace `hook.test.sh`;
     - flip `repository-layout.test.mjs:34` and `validate-repository.mjs:47-50`;
     - add a stray-reference check that excludes `docs/superpowers/**` and the translation table.
   - Migration README covering: re-pointing the `darkraise` marketplace (settings currently use
     `darkraise/claude-code-plugins`; the manifests name `darkraise/darkraise-plugins`; confirm
     the canonical remote); `dcc-statusline` → `dr-status`; `dcc-telegram-notify` (not in this
     catalog); disabling `superpowers`, `dcc-superpower-companions` and `andrej-karpathy-skills`.
   - Otherwise behaviour unchanged.
2. **Fold the companion skills in.**
   - `assigning-implementers` goes into writing-plans; `dispatching-tiered-implementers` into
     subagent-driven-development, with the external-executor lane moved to
     `reference/external-executor.md`.
   - Add `{#scope}`, the four-score schema, legacy-name translation (`superpowers:`,
     `dcc-superpower-companions:`), R1 and R4.
   - Update `criteria.test.sh:57`.
3. **Session budget.** `context-size`, `repo-audit`, `handoff`, `resume-execution`,
   `session-budget.md`, R7 and R8, and the compaction-recovery rule.
4. **Small-model planning.** The plan header block, `plan-lint` (R11), plan review (R10), the
   amendments protocol (R2), R3, the Execution line (R6) and the R12 planning items.
5. **Inline mode.** An `executing-plans` rewrite on R1 and R5, after sub-projects 2 and 4.

**Amendment 2026-09-11 (plugin 1.1.0): next-step guidance landed ahead of sub-project 3.**
`scripts/next-step` prints every session's next action (start or resume a task, final review,
next sub-project, program done) and rewrites the `## Next session` section of `latest.md`.
Plans carry an optional `**Program:** <spec> — sub-project <k> of <n> — next: <title>` header
line (`— last` on the final one), which is where the next sub-project comes from.
- Sub-project 3's `handoff` skill calls `next-step` rather than re-implementing it.
- Sub-projects 2, 4 and 5 rewrite the skills that call it (subagent-driven-development,
  dispatching-tiered-implementers, executing-plans, writing-plans,
  finishing-a-development-branch) and must keep those calls.

**Amendment 2026-09-11 (sub-project 3 spec).** Auto-compaction fires at about 93–96% of
`autoCompactWindow` (observed 467k–479k at 500000), so §3's claim that the 475k budget "fires
first" was false; the window is now 650000. R7 changes: the budget line is printed by
`task-brief` and `review-package` (no extra requests), and "final review done" is a soft stop.
A PreCompact hook cannot shape the summary, so the single-hook decision stands. Details:
`docs/superpowers/specs/2026-09-11-dr-superpowers-session-budget-design.md`.

**Amendment 2026-09-12 (sub-project 4 spec).** R2's plan-amender is not a separate seat: the
ruling seat (R3's strong judge) returns AMEND entries and the controller transcribes them through
`scripts/plan-amend`, which validates them. The seat has a fourth verdict, BLOCKED, the route to
the fourth stop class for a plan defect. writing-plans no longer offers an execution choice; the
Execution line decides. Details:
`docs/superpowers/specs/2026-09-12-dr-superpowers-small-model-planning-design.md`.

## 7. Verification (every sub-project)

- `node scripts/validate-repository.mjs`
- `node scripts/test-all.mjs`
- `claude plugin validate` on the marketplace and every plugin
- Bounded timeouts, and cleanup of every process started

## 8. Open risks

- Freezing at 6.3.0 forgoes upstream fixes, including in subagent-driven-development, the file
  that changes most often upstream.
- `context-size` depends on the transcript layout. Anthropic documents `transcript_path` but not
  the JSONL schema.
- Unverified:
  - whether Codex auto-triggers plugin skills from their descriptions alone;
  - whether a missing preloaded skill name in agent frontmatter errors or is ignored;
  - whether same-named skills in two enabled plugins double-trigger (the watchsound fork's
    README says they do).
- Subscription weighting is Unknown (§3).
