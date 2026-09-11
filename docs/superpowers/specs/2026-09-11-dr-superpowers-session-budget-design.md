# dr-superpowers 1.3.0 — session budget (sub-project 3 design)

Date: 2026-09-11. Program design: `docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`
(§3 cost model, §5 R4/R7/R8/R12, §6 item 3 and the next-step amendment). This spec amends R7 and
§3; the amendment is recorded under the program design's §6.

Reviewed as a draft by an independent Fable pass on 2026-09-11 (verdict: needs rework). Every
finding is resolved below. The reviewer's claim that a PreCompact hook can append text to the
compaction prompt was checked against the hooks reference and found false; §6 follows the
documented mechanism instead.

## 1. Decisions fixed here

- **`autoCompactWindow` is 650000** in `~/.claude/settings.json` (changed 2026-09-11, outside the
  plugin). Auto-compaction fires at about 93–96% of the window: observed at 467,031, 466,982 and
  479,296 tokens with the window at 500000 (inference from three events). At 500000 the 475k
  budget therefore never fired first. At 650000 compaction lands near 605–625k, leaving
  130k+ above the 475k budget.
- **The budget stays 475k** (owner ruling, program §3). `DR_SUPERPOWERS_BUDGET` overrides it.
- **Budget checks cost no extra requests.** `task-brief` and `review-package`, which the
  controller already runs before every task and every review, print the budget line.
  `scripts/context-size` is the standalone form for phases without those scripts.
- **One hook.** A PreCompact hook cannot shape the summary: the hooks reference documents only
  blocking (exit 2 or `decision: "block"`) and says Claude Code discards its `systemMessage` and
  `continue`. Preservation is done by the existing SessionStart hook on the `compact` source,
  which reads the full transcript (the JSONL keeps every pre-compaction entry).
- **`repo-audit`** is a read-only resume-orientation snapshot (owner answer; the program design
  named it without defining it).
- **Session-record fallback:** with no usable record, `context-size` uses the newest transcript
  for the directory and says the source is a guess (owner answer).
- **Codex keeps R7's count rule:** hand off every 3 tasks, or after any task that needed 3 or
  more fix rounds. No Codex measurement (owner answer).
- **Stops.** Hard: plan saved; all tasks complete (the final review runs in a fresh session).
  Soft: final review clean — finish in-session unless the budget line says handoff (owner
  answer; finishing is 10–15 requests, so a reload costs about what it saves).
- **Version 1.3.0** on both manifests.

## 2. File layout

New:
- `scripts/context-size`, `scripts/repo-audit`
- `scripts/lib/plan.sh` — the fence-aware `Task N` heading parser, moved out of `next-step`
- `scripts/lib/context.sh` — transcript lookup and measurement, shared by `context-size`,
  `task-brief` and `review-package`
- `scripts/lib/snapshot.sh` — the compaction snapshot, sourced by `session-start.sh`
- `skills/handoff/SKILL.md`, `skills/resume-execution/SKILL.md` (16 skills)
- `reference/session-budget.md`
- `tests/context-size.test.sh`, `tests/repo-audit.test.sh`, `tests/snapshot.test.sh`, with
  fixture transcripts under `tests/fixtures/`

Changed: `scripts/session-start.sh`, `scripts/next-step`, `scripts/task-brief`,
`scripts/review-package`; SKILL.md of subagent-driven-development, executing-plans,
finishing-a-development-branch, brainstorming, using-superpowers; `README.md`; both manifests;
`tests/next-step.test.sh`, `tests/hook.test.sh`; repository layout and validator expectations
for the two new skills.

## 3. Measuring context (`scripts/lib/context.sh`, `scripts/context-size`)

**Transcript lookup.** For each candidate directory — `$PWD`, the repository root, the primary
checkout — in that order:
1. Record `~/.claude/dr-superpowers/sessions/<key>.json`, key = the directory with
   non-alphanumerics replaced by `-` (the SP1 contract). Usable when its `transcript_path` exists.
2. Otherwise the newest `*.jsonl` directly in `~/.claude/projects/<key>/` (Claude Code's own
   naming; names over 200 characters are truncated with a hash suffix, so a missing directory
   is simply a miss). Source is `guessed`.

First hit wins. When a record is used but a newer `*.jsonl` exists in the same project directory
whose name is not the record's `session_id`, the source is `record?` — two sessions share the
directory and the record may belong to the other one.

**Measurement.** Main-chain entries only (`isSidechain` false). Find the last
`type == "system"`, `subtype == "compact_boundary"` entry. After it, take the last
`type == "assistant"` entry whose `message.model` is not `<synthetic>` and whose usage sum is
non-zero; context = `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. If
no such entry follows the boundary, use the boundary's `compactMetadata.postTokens`. With no
boundary, the last qualifying assistant entry. Zero-usage entries are interrupted requests and
never count.

**Budget line** (one line, all three scripts):
`budget: 312k of 475k (66%) — ok — source: record`
Verdicts: `ok`, `handoff` (at or over budget), `unknown` (no transcript, no qualifying entry, or
no `jq`). On Codex there is no record and usually no Claude transcript; `unknown` there means
"apply the count rule".

**`context-size`** prints the budget line. Exit 0 ok, 5 handoff, 3 unknown, 2 usage.
`task-brief` and `review-package` append the budget line after their existing output and keep
their own exit codes; a measurement failure never fails them.

## 4. `scripts/repo-audit`

Read-only; exit 0, or 2 outside a git repository. Prints markdown, about 40 lines:
- repository root and primary checkout; branch, HEAD (short sha and subject), ahead/behind its
  upstream
- `git worktree list`, marking prunable entries
- dirty files (`git status --short`), first 20 and a count
- plans in flight: every `.superpowers/sdd/*/progress.md` in the primary checkout and each
  worktree — plan path from the ledger's first line, "N of M tasks complete" (M from
  `lib/plan.sh`), last ledger line, whether `handoff.md` exists
- `latest.md`: its Status and Next lines, and the number of commits on the primary checkout's
  HEAD since the file was last written (staleness signal)
- whether the project-root CLAUDE.md has a "Compact Instructions" section
- the budget line
- last five commits

Sessions that resume work (`resume-execution`, the compaction recovery rule, the entry point's
resume guidance) run it first; it replaces the 5–8 orientation calls observed at every resume.

## 5. Handoff and resume

**`next-step` changes.**
- `--draft DRAFT_FILE --next "<action>"`: the design-phase block. Status names the draft as the
  authority; launch `claude --model opus --effort high`; prompt "Continue `<draft>` with
  dr-superpowers:brainstorming: <action>. The draft is the authority; read
  `.superpowers/handoff/latest.md` first." Writes latest.md's Next session section like plan
  mode.
- When a ledger exists, the resume prompt names `dr-superpowers:resume-execution` in place of the
  execution skill. A plan with no ledger keeps today's "Start at Task 1" prompt.
- A ledger whose tasks are all complete and that holds a `Final review: clean` line yields
  "Next: run dr-superpowers:finishing-a-development-branch."
- Task counting comes from `lib/plan.sh`; exit codes unchanged.

**`handoff` skill.** Fires when a budget line said `handoff` (acted on at the next ledger write,
so the ledger is always at a state the Recovery table resumes cleanly), at a hard stop, on the
Codex count rule, or when the owner asks. Steps:
1. Execution: make sure the ledger's last line is written. Update
   `<worktree>/.superpowers/sdd/<plan>/handoff.md` (below). Design phase: make sure the draft is
   saved.
2. Commit the plan and spec if either has uncommitted changes (R8); never commit
   `.superpowers/`.
3. Rewrite the notes sections of `<primary>/.superpowers/handoff/latest.md` — State (absolute
   worktree path, handoff.md path, ledger path), Gotchas, Do not — keeping each under 15 lines.
4. Run `next-step PLAN_FILE` (or `--draft`). The final message ends with its block verbatim:
   that is the resume guide of R8.

**`handoff.md`** (≤40 lines; the ledger stays the authority for task state): owner constraints
given during execution, gotchas, do-nots, open questions for the owner. Written at SDD Setup and
updated in the same message as the ledger write whenever one of those changes — not after every
task, since task state lives in the ledger and git.

**`resume-execution` skill.**
1. Run `repo-audit`; read latest.md.
2. Verify the worktree through `git worktree list`, comparing paths after normalising Windows
   and Git Bash forms. Missing but its branch exists: the entry may be prunable — prune and
   re-add it, and ledger a Ruling. Missing with no branch: stop and ask. HEAD no longer
   descending from the ledger's last complete commit (amend, rebase): ledger a Ruling and
   continue from the ledger and `git log`.
3. Enter the worktree; read handoff.md, the plan header and the ledger.
4. Invoke the plan's execution skill (Execution line); its ledger recovery takes over.

## 6. Compaction

**Avoid.** The window change (§1) plus the budget line at every task and every review.

**Recover.** On `source == "compact"`, `session-start.sh` appends a snapshot to the injected
context, built by `lib/snapshot.sh` from the stdin `transcript_path` and the repository:
1. Recovery rule, three lines: this session was compacted; trust this snapshot, the ledger and
   `git log` over the summary; run `repo-audit` if anything is unclear, and hand off if the
   budget line says so.
2. latest.md's Next session block.
3. For each ledger in the repository's worktrees: its last 8 lines and every `Ruling:` line
   (most recent 10).
4. Files written or edited by the main session (`Write`, `Edit`, `NotebookEdit` inputs), most
   recent 20, unique.
5. The last 3 genuine owner prompts (main-chain `user` entries with string content, not
   `isMeta`, not `isCompactSummary`, not tool results), 300 characters each.
6. Background agent ids from the most recent 5 `Agent` dispatches with their descriptions.

Hook output is capped at 10,000 characters (hooks reference), including the entry point
(~3.4k). The snapshot is capped at 5,500 characters; sections are truncated from 6 up to 3, and
sections 1–2 are never cut. Without `jq`, sections 3–6 are skipped. Other sources inject nothing
new.

**Skill truncation.** After compaction each invoked skill body is re-injected, capped at 5,000
tokens per skill, keeping the start of the file (context-window docs). subagent-driven-development
is ~45KB and executing-plans will grow, so both gain a ten-line "After compaction" block directly
under the frontmatter: re-read the ledger, trust it and git over memory, apply the Recovery table,
and hand off when the budget line says so.

**Summary shaping.** The README documents a "Compact Instructions" section for the project-root
CLAUDE.md (documented in how-claude-code-works): preserve verbatim the worktree path, ledger and
handoff paths, HEAD, every owner constraint, every Ruling, and pending questions. `repo-audit`
reports whether it is present. The plugin never edits CLAUDE.md.

## 7. Checkpoints in the skills

- **subagent-driven-development.** Setup writes handoff.md. The budget line arrives with every
  `task-brief` and `review-package`; on `handoff`, write the ledger line in progress, then invoke
  dr-superpowers:handoff. After the last `Task N: complete`, hand off (hard stop). The Finish
  section no longer deletes the workspace: it writes `Final review: clean (commits a..b)`, prints
  "Rulings I made" from the ledger, and continues to finishing unless the budget says handoff.
  New ledger grammar line: `Final review: clean (commits a..b[, K parked])`.
- **executing-plans.** The same checks at the same points (minimal insertion; sub-project 5
  rewrites the skill).
- **brainstorming.** One `context-size` check after the spec commit: on `handoff`, write the plan
  in a fresh session (`next-step --draft`).
- **finishing-a-development-branch.** Step 6 deletes the plan's workspace only for Option 1 and
  confirmed discards: worktree removal takes it when the workspace lives in the worktree;
  otherwise `rm -rf <workspace>` after the merge is verified. Options 2 and 3 keep it. Before
  Step 4, if a ledger exists and its rulings were not printed this session, print "Rulings I
  made". Step 1's note about a deleted ledger is updated.
- **using-superpowers.** A short Session budget section: the budget line and what `handoff`
  means; resume sessions run `repo-audit` first; after more than an hour idle, start a fresh
  session from latest.md instead of continuing (the one-hour cache is cold, and Claude Code
  offers "Resume from summary" in that case); the compaction rule. The ≤1.2k-token rewrite is
  sub-project 4.

## 8. `reference/session-budget.md`

The numbers and why (475k budget, 650000 window, observed trigger ratio, 10,000-character hook
cap, 5,000-token skill cap), the Codex count rule, the stops, the checkpoint list above, the
recovery rule, the idle rule, and the Compact Instructions block to paste into CLAUDE.md.
Program §3 stays the cost reference.

## 9. Verification

Program design §7: `node scripts/validate-repository.mjs`, `node scripts/test-all.mjs` (the known
`rg`-missing failure in `ui-discovery.test.mjs` is environmental), `claude plugin validate` on the
marketplace and every Claude plugin; bounded timeouts; every started process cleaned up.

Tests:
- `context-size.test.sh`: record source, fallback with warning, `record?` on a mismatched
  session id, sidechain and `<synthetic>` entries ignored, zero-usage entry skipped, boundary
  with and without a following assistant entry (`postTokens`), over-budget exit 5, no usage
  exit 3, `DR_SUPERPOWERS_BUDGET` override, CRLF input; `task-brief` and `review-package` keep
  their exit codes when measurement fails.
- `repo-audit.test.sh`: temporary repository with a worktree, a ledger, a stale latest.md, and
  a CLAUDE.md with and without Compact Instructions.
- `snapshot.test.sh`: each section from a fixture transcript, the 5,500-character cap and its
  truncation order, no `jq`.
- `hook.test.sh`: the compact source appends the snapshot; other sources do not; total output
  under 10,000 characters.
- `next-step.test.sh`: `--draft`, the resume-execution prompt, `Final review: clean`.

## 10. Out of scope

The ≤1.2k-token entry point and the other R12 items, plan header, plan-lint, plan review,
amendments and R3 (sub-project 4); the executing-plans rewrite (5); the Windows `jq`
argument-length failure in `run-codex-task.sh` (parked from sub-project 2). The
`plugins/darkmem-resume/` directory is the owner's live work: never touched or committed.

## 11. Risks

- The transcript fields used (`isSidechain`, `compact_boundary`, `compactMetadata.postTokens`,
  `isCompactSummary`, `message.usage`) are observed, not documented. Fixtures pin them; a schema
  change degrades the verdict to `unknown` and the snapshot to sections 1–2, never a failed hook.
- The 93–96% trigger ratio is inferred from three events. `session-budget.md` says so.
- `git worktree remove` is assumed to delete ignored files such as `.superpowers/` without
  `--force`; the plan verifies it before relying on it.
- Two concurrent sessions in one directory can still measure the wrong transcript; `record?`
  flags it.
- Expected saving on a 10-task plan (reviewer's estimate): about 9% of weighted tokens and no
  compactions, for about 4% more requests. The 475k ruling forgoes most of the read savings.
