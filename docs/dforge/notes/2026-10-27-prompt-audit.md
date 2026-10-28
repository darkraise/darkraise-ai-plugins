# dforge prompt audit

**Run:** 2026-10-28, Claude Code 2.1.312.

**Scope:** `/doctor prompt-audit` ran on `--model sonnet` over a copy of `plugins/dforge/skills`, `agents`, `reference` and `criteria`, laid out as a project's `.claude/` directory, because the audit proposes edits for a project's own files and none for an installed plugin's. The request kept it inside that directory, so nothing of the owner's `~/.claude` is read or quoted. `/skill-doctor` reads the usage history of the owner's Claude config directory and makes no model call.

**Ruling:** `disable-model-invocation` is not proposed. dforge skills invoke each other through the Skill tool, so no dforge skill qualifies (spec ruling of 2026-10-28).

**Method:** nothing was edited. A proposal below is a finding of the audit that names a dforge file and whose action is not `flag`, or an explicit recommendation in the `/skill-doctor` output; each one is a deferred register row.

## /doctor prompt-audit

~~~~markdown
# Prompt audit: `.claude/` (project only)

## Assumptions

- **Scope:** only the 117 files under `/tmp/dforge-task6-work/project/.claude` (`agents/`, `criteria/`, `reference/`, `skills/`). I read nothing outside the project and listed no plugins. The project has no `CLAUDE.md`, no `.mcp.json`, and no settings or hook files under `.claude`.
- **Target model:** Claude Sonnet 5.5, the model running this audit. Each agent file that pins its own model is judged against that model.
- **Coverage:** the directory is about 17,400 lines. I grepped all of it for the pattern signals and read in full the 20 agent definitions (diffed against each other), `verification-before-completion`, and the relevant parts of `systematic-debugging`, `receiving-code-review`, `writing-skills`, `native-codex.md`, `assigning-implementers.md` and `using-dforge`. The other skills and reference files were covered by grep only, so absence of a finding there is not a clean bill.
- **No git history.** I could not run `git blame`, so nothing is dated by provenance and no finding is rated High on dating alone.
- **Not verified:** `scripts/plan-lint`, `scripts/ui-proof` and `scripts/depth-route` are cited, but the project has no `scripts/` directory. They look like part of an installed tool, so I did not treat their absence as a defect.
- **Paths checked:** every `criteria/`, `reference/` and `references/` path cited inside `.claude` resolves to a real file. The exceptions are the example paths inside `anthropic-best-practices.md`.

## Summary

The surface is mostly healthy. The recurring dated pattern is pressure-and-rationalization scaffolding in the discipline skills. It is written in a forceful register (`ALWAYS`, `MUST`, "Iron Law", "Skip any step = lying") that Sonnet 5.5 reads more literally than the older models it was written for. The second theme is text that will rot: pinned model names copied into all 20 agent bodies, and incident or version archaeology in the reference files.

| Group | Findings |
|---|---|
| 1 Dated prompt text | 5 (1a: 3, 1c: 1, 1d: 1) |
| 2 Brittle config files | 4 (3 of them flag-only) |
| 3 Tool descriptions | not applicable (no tool definitions) |
| 4 Request config | not applicable. I checked the agent roster: the `impl-*` files differ only in `model` and `effort` frontmatter, which a payload can't carry, so they are not redundant. |

## Findings, ordered by confidence

### 1. Medium: pressure language in `skills/systematic-debugging/SKILL.md`
- **Evidence:**
  - line 10: `ALWAYS find root cause before attempting fixes. Symptom fixes are failure.`
  - line 12: `Violating the letter of this process is violating the spirit of debugging.`
  - line 46: `You MUST complete each phase`
  - line 50: `BEFORE attempting ANY fix:`
  - line 24: `ANY technical issue`
  - line 32: `ESPECIALLY`
- **Pattern:** 1a.
- **Why obsolete:** the register is anxious, and current models over-apply it. The reasons are already in the file.
- **Action:** rewrite (hunk 1).

### 2. Medium: the same register in `skills/verification-before-completion/SKILL.md`
- **Evidence:**
  - line 12: the "letter of this rule" line.
  - line 35: `Skip any step = lying, not verifying`
  - line 60: `ANY wording implying success`
  - lines 58–59: `Thinking "just this once"` and `Tired and wanting work over`
  - table rows `"I'm tired"`, `"Just this once"` and `"Different words so rule doesn't apply"`.
- **Pattern:** 1a and 1e. These are tic and trait claims with no observable constraint behind them.
- **Why obsolete:** "tired" describes a human, not the model. The Iron Law, the Gate Function and the Common Failures table are the real contract, and they stay.
- **Action:** rewrite and remove (hunk 2).

### 3. Medium: banned-phrase list in `skills/receiving-code-review/SKILL.md:27-38`
- **Evidence:** `**NEVER:** "You're absolutely right!" (explicit instruction-file violation) …`
- **Pattern:** 1e (an output-style prohibition with no provenance). The parenthetical also points at an instruction-file rule that doesn't exist in this project, so it is a dangling reference.
- **Why obsolete:** the positive form is already in the `INSTEAD` list, and naming the phrases anchors toward them.
- **Action:** rewrite (hunk 3).

### 4. Medium: one rule stated four times in `skills/writing-skills/SKILL.md`
- **Evidence:** lines 102 and 180 (`**NEVER summarize the skill's process or workflow**`) and line 150 (`**CRITICAL: Description = When to Use, NOT What the Skill Does**`), plus 152 and 158 restating it.
- **Pattern:** 1c padding, plus 1a on the `CRITICAL` header.
- **Why obsolete:** the reasoned account at lines 154–158 is the useful part and stays. The repeats add weight, not information. This is authoring guidance, not a skill's trigger `description`, so the urgency doesn't qualify for the trigger-text exception.
- **Action:** remove and rewrite (hunk 4).

### 5. Medium: model identity copied into every agent body
- **Evidence:** `You run on Sonnet 5.5 at low effort.` (line 14 or 15 of all 20 files in `agents/`), duplicating the `model:` and `effort:` frontmatter.
- **Pattern:** Group 2, pinned model names.
- **Why obsolete:** frontmatter is the source of truth. `model: sonnet`, `model: opus` and `model: haiku` are aliases, so the body text will silently disagree after the next release. `impl-haiku.md` already hits this: the body says Haiku 4.5, but Haiku 5.5 is the current generation.
- **Action:** remove (hunk 5).

### 6. Medium: archaeology in `skills/writing-plans/references/assigning-implementers.md:93-99`
- **Evidence:** `These rules used to be a checklist the planner ran against its own work, and a planner grading itself passes what it meant rather than what it wrote.`
- **Pattern:** 1d, migration-relative phrasing.
- **Why obsolete:** "used to be" is a diff against a prior version. The live fact is that a script checks the plan.
- **Action:** rewrite (hunk 6).

### 7. Medium: dated vendor narrative in `reference/native-codex.md:48-53`
- **Evidence:** `codex-v4 (2026-10-07) moved ranks 3 to 6 from gpt-6-sol to gpt-6.1-sol, Codex's default model since 0.159.1, on OpenAI's description of it as near-Astra on software work`
- **Pattern:** Group 2 history narrative and volatile specifics.
- **Why obsolete:** the date, client version and vendor marketing phrase rot. The current ranks are in the table above, and the "no calibration replay" caveat is worth keeping.
- **Action:** rewrite (hunk 7). The v3 rank table at lines 82–91 stays because the conversion rules at lines 72–80 use it.

### 8. Low (flag only): `impl-sonnet-low.md:34-40` has a paragraph the other 19 agents lack
- **Evidence:** `When you change code that can be run, built, or type-checked, run a real check…`
- **Pattern:** possible patch accretion (Group 1d) or recency trap (Group 2).
- **Why flagged:** I can't tell whether this is a deliberate low-effort guard or a one-off patch. Every `impl-*` agent preloads `dforge:verification-before-completion`, which already covers it. The user decides whether to keep it, copy it to every `impl-*` agent, or drop it.

### 9. Low (flag only): rationalization tables and "Red Flags – STOP" blocks across about ten skills
- **Where:** `verification-before-completion`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `requesting-code-review`, `subagent-driven-development`, `writing-skills`, `parallel-waves.md:349` and others.
- **Pattern:** idiom-dating (1c).
- **Why flagged:** `writing-skills` documents these as deliberate (`persuasion-principles.md`), and a failure this scaffold prevents may still reproduce. Test removals on Sonnet 5.5 with the pressure scenarios in `references/testing-skills-with-subagents.md`, one skill at a time, before cutting anything.

### 10. Low (flag only): skill size bounds conflict with each other and with the repo
- **Evidence:** `writing-skills/SKILL.md:218-220` says `<500 words`. `references/anthropic-best-practices.md:241` says `under 500 lines`. Six skills exceed 500 lines: `subagent-driven-development` (733), `writing-skills` (679), `writing-plans` (671), `brainstorming` (658), `executing-plans` (602) and `finishing-a-development-branch` (589).
- **Pattern:** Group 2, verbose `SKILL.md` and conflicting instructions.
- **Why flagged:** the two bounds use different units, so they aren't strictly opposed, and no history shows which is current. Splitting those skills is a refactor, not a cruft edit. Choose one bound and state it once.

### 11. Low (flag only): `systematic-debugging/SKILL.md:278`
- **Evidence:** `But: 95% of "no root cause" cases are incomplete investigation.`
- **Why flagged:** an unsourced statistic. Soften it or cite where it comes from.

## Kept, not flagged

- Trigger text with urgency: `brainstorming` `description` ("You MUST use this…").
- Fragile-operation requirements: `using-git-worktrees:82` (verify the directory is ignored first) and `writing-plans:110` (required plan header).
- The `Common Failures` and `Gate Function` contracts in `verification-before-completion`.
- Tool and format contracts in `reference/` and `criteria/*.json`.
- The vendored `anthropic-best-practices.md`: its `MUST` examples are illustrative. Re-check it against current docs when convenient.

## Proposed diff

No files were edited. One finding per hunk.

```diff
--- hunk 1: skills/systematic-debugging/SKILL.md
-**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.
-
-**Violating the letter of this process is violating the spirit of debugging.**
+**Core principle:** Find the root cause before attempting a fix; a fix that treats a symptom leaves the bug in place.
@@ ~24
-Use for ANY technical issue:
+Use for any technical issue:
@@ ~32
-**Use this ESPECIALLY when:**
+**Use this most when:**
@@ ~46
-You MUST complete each phase before proceeding to the next.
+Complete each phase before starting the next; each builds on what the one before it established.
@@ ~50
-**BEFORE attempting ANY fix:**
+**Before attempting a fix:**

--- hunk 2: skills/verification-before-completion/SKILL.md
-**Violating the letter of this rule is violating the spirit of this rule.**
-
@@ ~35
-Skip any step = lying, not verifying
+A skipped step leaves the claim unverified.
@@ ~58-60
-- Thinking "just this once"
-- Tired and wanting work over
-- **ANY wording implying success without having run verification**
+- Any wording that implies success before verification has run
@@ rationalization table
-| "Just this once" | No exceptions |
-| "I'm tired" | Exhaustion ≠ excuse |
-| "Different words so rule doesn't apply" | Spirit over letter |

--- hunk 3: skills/receiving-code-review/SKILL.md
-**NEVER:**
-- "You're absolutely right!" (explicit instruction-file violation)
-- "Great point!" / "Excellent feedback!" (performative)
-- "Let me implement that now" (before verification)
-
-**INSTEAD:**
+Open with the technical content, not agreement or praise, and verify before saying you will implement:
 - Restate the technical requirement
 - Ask clarifying questions
 - Push back with technical reasoning if wrong
 - Just start working (actions > words)

--- hunk 4: skills/writing-skills/SKILL.md
@@ 102
-  - **NEVER summarize the skill's process or workflow** (see SDO section for why)
@@ 150
-**CRITICAL: Description = When to Use, NOT What the Skill Does**
+**Description = when to use, not what the skill does**
@@ 180
-- **NEVER summarize the skill's process or workflow**

--- hunk 5: agents/*.md (all 20 files)
-You run on <Model> at <effort> effort.
   (delete this one sentence in each file; frontmatter `model:` / `effort:` stays authoritative)

--- hunk 6: skills/writing-plans/references/assigning-implementers.md
-These rules used to be a checklist the planner ran against its own work, and a
-planner grading itself passes what it meant rather than what it wrote.
-`scripts/plan-lint` applies the same checks the same way whichever model wrote
-the plan, and it reads `ladder.md`'s tables at run time, so the checks cannot
-drift from the tables they enforce.
+`scripts/plan-lint`, not the planner, checks these rules: it applies the same
+checks whichever model wrote the plan, and it reads `ladder.md`'s tables at run
+time, so the checks cannot drift from the tables they enforce.

--- hunk 7: reference/native-codex.md
-These tiers are policy choices, not benchmark results. codex-v4 (2026-10-07)
-moved ranks 3 to 6 from `gpt-6-sol` to `gpt-6.1-sol`, Codex's default model
-since 0.159.1, on OpenAI's description of it as near-Astra on software work;
-no calibration replay was run for the move. Only currently advertised
+These tiers are policy choices, not benchmark results, and no calibration
+replay backs them. Only currently advertised
 and user-allowed model/effort pairs can run; API model availability does not
 establish access through a native client or the external CLI.
```

Findings 8 to 11 are report-only, so they have no hunks. Hunk 5 touches 20 files. If you want to keep the sentence in some of them, take hunk 5 selectively. I didn't run the behavioral probes from Step 7 of the guide (a before and after check on each change), so test hunks 1 to 3 on Sonnet 5.5 before relying on them.
~~~~

## /skill-doctor

~~~~text
Skills loaded this session

  skill                                  source  context  7d tokens   uses  last used
  dforge:closing-a-milestone             dforge      ~90          -     0×  never
  dforge:distilling-docs                 dforge      ~80          -     0×  never
  dforge:migrate                         dforge      ~80     111.8k     0×  never
  dforge:planning-a-product              dforge      ~80          -     0×  never
  dforge:project-status                  dforge      ~70     417.7k     0×  never
  dforge:receiving-code-review           dforge      ~90      15.6m     0×  never
  dforge:requesting-code-review          dforge      ~50          -     0×  never
  dforge:revising-plans                  dforge      ~80          -     0×  never
  dforge:running-gates                   dforge      ~70      11.9m     0×  never
  dforge:selecting-approaches            dforge      ~70          -     0×  never
  dforge:test-driven-development         dforge      ~40      27.2m     0×  never
  dforge:test-simplifier                 dforge     ~100          -     0×  never
  dforge:using-dforge                    dforge      ~60       175k     0×  never
  dforge:verification-before-completion  dforge      ~90          -     0×  never
  dforge:writing-skills                  dforge      ~40          -     0×  never
  dforge:executing-plans                 dforge      ~60       9.3m     4×  8 days
  dforge:ui-ux                           dforge     ~140       2.4m     1×  2 days
  dforge:brainstorming                   dforge      ~70     101.8m     8×  today
  dforge:finishing-a-development-branch  dforge      ~50      47.4m     8×  today
  dforge:handoff                         dforge     ~130     127.4m    14×  today
  dforge:resume-execution                dforge      ~80      12.1m     5×  today
  dforge:subagent-driven-development     dforge      ~40      72.2m     7×  today
  dforge:systematic-debugging            dforge      ~40      41.3m     3×  today
  dforge:using-git-worktrees             dforge      ~80     104.5m     6×  today
  dforge:writing-plans                   dforge      ~40     924.6m     8×  today

  context = this skill's one-line listing in the system prompt, included every turn
  (dash = not in the current listing, costs nothing; full SKILL.md loads only when it runs)
  7d tokens = tokens attributed to the skill over the last 7 days of sessions on this machine

~~~~

## Proposed changes

- P1: Rewrite the pressure language in plugins/dforge/skills/systematic-debugging/SKILL.md so it states its reasons (ALWAYS, MUST, ESPECIALLY, letter-of-the-process line)
- P2: Remove the tiredness and just-this-once rationalizations and the lying line in plugins/dforge/skills/verification-before-completion/SKILL.md, keeping the Iron Law and Gate Function
- P3: Rewrite the NEVER phrase list in plugins/dforge/skills/receiving-code-review/SKILL.md as a positive instruction and drop the dangling instruction-file reference
- P4: Remove the repeated NEVER summarize and CRITICAL description rule in plugins/dforge/skills/writing-skills/SKILL.md, keeping the reasoned account of lines 154-158
- P5: Remove the sentence naming the model and effort from the body of every plugins/dforge/agents/*.md file, since frontmatter is the source of truth
- P6: Rewrite the used-to-be checklist history in plugins/dforge/skills/writing-plans/references/assigning-implementers.md to state only that plan-lint checks the rules
- P7: Rewrite the dated codex-v4 vendor narrative in plugins/dforge/reference/native-codex.md, keeping the no-calibration-replay caveat and the v3 rank table
