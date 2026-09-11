# dr-superpowers Standalone Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

**Goal:** Turn `plugins/dr-superpowers` into a standalone 1.0.0 fork of superpowers 6.3.0 — skills copied in, hook swapped to SessionStart, dependency dropped — with the validator, tests, migration README and licenses that lock the new shape in.

**Architecture:** Thirteen upstream skills are copied from the installed 6.3.0 cache, surgically trimmed (visual companion, dropped hosts, parallel-agents references), renamed to the `dr-superpowers:` prefix, and rearranged into the target layout (per-skill `references/`, sdd scripts at plugin `scripts/`). The PreToolUse tier-nudge is replaced by a SessionStart hook that injects the using-superpowers entry point (which now carries the companion-skill routing) and persists the session's transcript path. Manifests go to 1.0.0 with no dependency, and the repository validator gains flipped dependency checks plus a legacy-prefix stray-reference check.

**Tech Stack:** Bash (Git Bash on Windows) + jq for hooks and shell tests; Node 22 (`node:test`) for the repository validator and layout tests; Claude Code / Codex plugin manifests.

**Spec:** `docs/superpowers/specs/2026-09-11-dr-superpowers-standalone-base-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Tasks 6 and 7 score 4, so R5 inline eligibility fails; every task is mechanical enough for Sonnet/Haiku implementers under dispatching-tiered-implementers with its review loop.

Execute in a worktree (superpowers:using-git-worktrees) branched from `docs/dr-superpowers-fork-design`, which carries the spec and this plan.

## Global Constraints

- Copy source is the installed upstream cache: `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/` (referred to below as `$SRC`). Never modify anything under the cache.
- Never touch `plugins/darkmem-resume/` (owner's live work) or historical docs under `docs/superpowers/`. Never push. Never merge to main.
- Claude and Codex plugin manifest versions stay equal: both become `1.0.0`. Claude marketplace catalog becomes `0.4.0`.
- Prefix rule (enforced by Task 8's check): no `superpowers:` (unless preceded by `dr-`) and no `dcc-superpower-companions:` anywhere under `plugins/{dr-superpowers,dr-status,dcc-darkraise-ui,dcc-darkraise-win32ui}`, except the reserved path `plugins/dr-superpowers/reference/legacy-names.md` (created by sub-project 2, not here).
- Commits: `<type>(superpowers): <subject>`, subject ≤50 chars, imperative, English.
- Every test/CLI run bounded with a timeout; kill any process you start; `node scripts/test-all.mjs` already bounds and kills its children.
- All paths below are relative to the repository root unless absolute.

## Contracts

- **Session record** (produced by Task 6, consumed by sub-project 3): JSON file at `~/.claude/dr-superpowers/sessions/<key>.json` where `<key>` is the hook payload's `cwd` with every character outside `A-Za-z0-9` replaced by `-`; body `{"session_id":"...","transcript_path":"...","cwd":"...","source":"...","timestamp":"<UTC ISO-8601>"}`. Last writer wins per cwd.
- **Hook shape**: `hooks/hooks.json` registers only SessionStart, matcher `startup|resume|clear|compact`, command `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"`, `"shell": "bash"`, `"async": false`.
- **Validator error strings** (asserted by tests): `dr-superpowers: standalone plugin must not declare dependencies`; `claude: cross-marketplace dependency allowlist must be removed`; `<path>:<line>: legacy plugin-name reference`.
- **Script locations**: `sdd-workspace`, `task-brief`, `review-package` live at `plugins/dr-superpowers/scripts/` (they resolve each other via `dirname "$0"`, so they move together).

## Assumptions (evidence)

- The upstream 6.3.0 cache exists at `$SRC` with the file inventory this plan enumerates (listed 2026-09-11 in the design session).
- `jq`, Git Bash, and GNU coreutils are present (the existing `plugins/dr-superpowers/tests/*.test.sh` already require them).
- Node 22 supports regex lookbehind (V8 has since Node 8.3; `validate-repository.mjs` already targets Node 22 per CI).
- `claude` CLI is on PATH for `claude plugin validate` (repo CLAUDE.md names it as a required validation step).
- `andrej-karpathy-skills` declares MIT in its README and ships no LICENSE file (checked in its installed cache 2026-09-11).

## Task index

1. Copy the 13 upstream skills; drop excluded files; fix the one broken link
2. Wording surgery: visual companion out, hosts trimmed, parallel-agents refs replaced
3. Rename legacy prefixes across the plugin
4. Move per-skill supporting docs into `references/` and fix links
5. Move the sdd scripts to plugin `scripts/` and update path references
6. Hook swap: SessionStart hook, session-start.sh, new hook.test.sh
7. Manifests to 1.0.0 standalone; validator flip; layout test cases
8. Stray-reference check in the validator
9. README migration section, hook rewrite, LICENSES/
10. Full verification sweep

---

### Task 1: Copy the 13 upstream skills; drop excluded files; fix the one broken link

**Files:**
- Create: `plugins/dr-superpowers/skills/<name>/` for the 13 skills listed in Step 1
- Modify: `plugins/dr-superpowers/skills/writing-skills/SKILL.md` (one sentence)

**Interfaces:**
- Consumes: nothing
- Produces: the 13 copied skill directories that Tasks 2–5 edit in place

**Implementer:** dcc-superpower-companions:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Copy the skills**

From the repository root, in Git Bash (`$SRC` expands the cache path; adjust `$HOME` spelling if needed):

```bash
SRC="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0"
for s in using-superpowers brainstorming writing-plans executing-plans \
         subagent-driven-development test-driven-development systematic-debugging \
         verification-before-completion requesting-code-review receiving-code-review \
         finishing-a-development-branch using-git-worktrees writing-skills; do
  cp -r "$SRC/skills/$s" plugins/dr-superpowers/skills/
done
```

`dispatching-parallel-agents` is deliberately not copied.

- [ ] **Step 2: Delete the excluded files**

```bash
cd plugins/dr-superpowers/skills
rm -r brainstorming/scripts
rm brainstorming/visual-companion.md
rm using-superpowers/references/pi-tools.md \
   using-superpowers/references/antigravity-tools.md \
   using-superpowers/references/hermes-tools.md \
   using-superpowers/references/gemini-tools.md
rm systematic-debugging/CREATION-LOG.md systematic-debugging/test-academic.md \
   systematic-debugging/test-pressure-1.md systematic-debugging/test-pressure-2.md \
   systematic-debugging/test-pressure-3.md
```

The systematic-debugging deletions are eval fixtures; the audit (2026-09-11) confirmed no SKILL.md links them. `brainstorming/spec-document-reviewer-prompt.md` and `writing-plans/plan-document-reviewer-prompt.md` are kept (sub-project 4 adapts the latter).

- [ ] **Step 3: Fix the now-broken gemini link in writing-skills**

In `plugins/dr-superpowers/skills/writing-skills/SKILL.md`, replace:

```
**Personal skills live in your runtime's skills directory** (`~/.claude/skills/` on Claude Code) — see [codex-tools.md](../using-superpowers/references/codex-tools.md) or [gemini-tools.md](../using-superpowers/references/gemini-tools.md) for the path on those runtimes. Codex, Copilot CLI, and Gemini CLI all also recognize `~/.agents/skills/` as a cross-runtime alias.
```

with:

```
**Personal skills live in your runtime's skills directory** (`~/.claude/skills/` on Claude Code) — see [codex-tools.md](../using-superpowers/references/codex-tools.md) for the path on Codex, which also recognizes `~/.agents/skills/` as a cross-runtime alias.
```

- [ ] **Step 4: Verify**

Run: `node scripts/validate-repository.mjs` (60s timeout)
Expected: `Repository catalogs, manifests, versions, and bundled links are valid.` (the bundled-link check now covers the copied skills)

Run: `ls plugins/dr-superpowers/skills`
Expected: exactly 16 directories — the 13 above plus the existing assigning-implementers, dispatching-tiered-implementers, selecting-approaches.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills
git commit -m "feat(superpowers): copy upstream 6.3.0 skills"
```

---

### Task 2: Wording surgery: visual companion out, hosts trimmed, parallel-agents refs replaced

**Files:**
- Modify: `plugins/dr-superpowers/skills/brainstorming/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/using-superpowers/references/codex-tools.md`
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md`
- Modify: `plugins/dr-superpowers/skills/selecting-approaches/SKILL.md`

**Interfaces:**
- Consumes: the copied skills from Task 1
- Produces: skill texts free of the visual companion, dropped hosts, and `dispatching-parallel-agents`

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

All old-text anchors below are verbatim from the 6.3.0 files; if an anchor does not match exactly, stop and report rather than improvising.

- [ ] **Step 1: brainstorming — remove the visual-companion checklist item**

In the `**Architectural:**` checklist, delete item 2 entirely:

```
2. **Offer the visual companion just-in-time** — NOT upfront. The first time a question would genuinely be clearer shown than described, offer it then (its own message); on approval its browser tab opens for you. If no visual question ever arises, never offer it. See the Visual Companion section below.
```

then renumber the remaining items 3–9 to 2–8 (their text is unchanged).

- [ ] **Step 2: brainstorming — remove the Visual Companion section**

Delete everything from the line `## Visual Companion` through the end of the file (it is the final section, ending with the line that names `skills/brainstorming/visual-companion.md`).

- [ ] **Step 3: brainstorming — add the Artifact note**

In the `**Presenting the design:**` bullet list, after the bullet `- Cover: architecture, components, data flow, error handling, testing`, insert:

```
- On Claude Code, when an option is genuinely clearer shown than described, present it visually with the Artifact tool
```

Also confirm (grep) that no other mention of `visual companion`, `visual-companion`, `start-server`, or `stop-server` remains in `skills/brainstorming/`; delete any leftover sentence that offers the companion.

- [ ] **Step 4: using-superpowers — trim the platform table to Codex**

Replace:

```
- Codex: `references/codex-tools.md`
- Pi: `references/pi-tools.md`
- Antigravity: `references/antigravity-tools.md`
- Hermes Agent: `references/hermes-tools.md`
```

with:

```
- Codex: `references/codex-tools.md`
```

- [ ] **Step 5: using-superpowers — add companion routing**

In the `## Skill Priority` section, after the two example bullets (`- "Let's build X" → ...` and `- "Fix this bug" → ...`), insert:

```
- An approach decision is open (during brainstorming, or a plan task whose approach is undecided) → superpowers:selecting-approaches gates it.
- Writing a plan → superpowers:assigning-implementers records each task's implementer.
- Executing a plan with subagents → superpowers:dispatching-tiered-implementers dispatches and escalates them.
```

(Task 3's rename turns these into `dr-superpowers:` names.) This routing replaces the deleted PreToolUse tier-nudge, so it must name all three companion skills.

- [ ] **Step 6: codex-tools — drop the parallel-agents mention**

In `using-superpowers/references/codex-tools.md`, replace:

```
This enables the multi-agent tools that skills like
`dispatching-parallel-agents` and `subagent-driven-development` use.
```

with:

```
This enables the multi-agent tools that skills like
`subagent-driven-development` use.
```

- [ ] **Step 7: executing-plans — trim the host list**

Replace:

```
**Note:** Tell your human partner that Superpowers works much better with access to subagents (Claude Code, Codex CLI, Codex App, Copilot CLI, and Gemini CLI all qualify; see the per-platform tool refs in `../using-superpowers/references/`). If subagents are available, use superpowers:subagent-driven-development instead of this skill.
```

with:

```
**Note:** Tell your human partner that Superpowers works much better with access to subagents (Claude Code and Codex both qualify; see `../using-superpowers/references/codex-tools.md` for Codex). If subagents are available, use superpowers:subagent-driven-development instead of this skill.
```

- [ ] **Step 8: selecting-approaches — replace the parallel-agents reference**

Replace:

```
parallel, one per candidate, per superpowers:dispatching-parallel-agents. Give
```

with:

```
parallel, one per candidate, dispatched in a single message so they run
concurrently. Give
```

- [ ] **Step 9: Verify**

Run: `grep -rn "dispatching-parallel-agents" plugins/dr-superpowers/`
Expected: no output.
Run: `grep -rn "pi-tools\|antigravity-tools\|hermes-tools\|gemini-tools" plugins/dr-superpowers/skills/`
Expected: no output.
Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid.

- [ ] **Step 10: Commit**

```bash
git add plugins/dr-superpowers/skills
git commit -m "feat(superpowers): trim companion, hosts, parallel refs"
```

---

### Task 3: Rename legacy prefixes across the plugin

**Files:**
- Modify: every file under `plugins/dr-superpowers/` containing `superpowers:` or `dcc-superpower-companions:` (skills, agents, criteria, reference, tests, README; the sweep finds them)

**Interfaces:**
- Consumes: Tasks 1–2 (so upstream anchors are already edited)
- Produces: a plugin whose only skill/agent prefix is `dr-superpowers:` — the state Task 8's checker enforces

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Run the rename sweep**

From the repository root, in Git Bash:

```bash
cd plugins/dr-superpowers
grep -rlE 'superpowers:|dcc-superpower-companions:' . | while read -r f; do
  sed -i 's/dcc-superpower-companions:/dr-superpowers:/g; s/\([^-]\)superpowers:/\1dr-superpowers:/g; s/^superpowers:/dr-superpowers:/' "$f"
done
```

The middle pattern skips anything already prefixed (`dr-superpowers:` has `-` before `superpowers:`); the third handles line-start occurrences. This also updates `tests/fleet.test.sh`'s expected preload string and the agents' `skills:` frontmatter in the same pass.

- [ ] **Step 2: Verify no stray prefix remains**

Run: `grep -rnoE '(^|[^-])superpowers:|dcc-superpower-companions:' plugins/dr-superpowers/`
Expected: no output. (`-o` prints only matches, so `dr-superpowers:` lines cannot mask a stray.)

- [ ] **Step 3: Run the plugin test suites**

Run: `node scripts/test-all.mjs` (bounded internally; ~10 min budget)
Expected: all suites pass — in particular `fleet.test.sh` (its expectation was renamed in the same sweep) and `hook.test.sh` (the tier-nudge's matcher strings and the test's synthetic skill names were renamed symmetrically, so it still passes until Task 6 replaces both).

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers
git commit -m "refactor(superpowers): rename legacy prefixes"
```

---

### Task 4: Move per-skill supporting docs into `references/` and fix links

**Files:**
- Rename (git mv) the supporting files listed in Step 1
- Modify: the SKILL.md files listed in Step 2

**Interfaces:**
- Consumes: Tasks 1–3
- Produces: the §4 target layout `skills/<name>/references/` that later sub-projects assume

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Move the files**

From the repository root:

```bash
cd plugins/dr-superpowers/skills
mkdir -p test-driven-development/references requesting-code-review/references \
         subagent-driven-development/references systematic-debugging/references \
         writing-skills/references brainstorming/references writing-plans/references
git mv test-driven-development/writing-good-tests.md test-driven-development/references/
git mv requesting-code-review/code-reviewer.md requesting-code-review/references/
git mv subagent-driven-development/implementer-prompt.md \
       subagent-driven-development/task-reviewer-prompt.md \
       subagent-driven-development/re-review-prompt.md \
       subagent-driven-development/references/
git mv systematic-debugging/root-cause-tracing.md systematic-debugging/defense-in-depth.md \
       systematic-debugging/condition-based-waiting.md \
       systematic-debugging/condition-based-waiting-example.ts \
       systematic-debugging/find-polluter.sh systematic-debugging/references/
git mv writing-skills/anthropic-best-practices.md writing-skills/persuasion-principles.md \
       writing-skills/graphviz-conventions.dot writing-skills/render-graphs.js \
       writing-skills/testing-skills-with-subagents.md writing-skills/references/
git mv writing-skills/examples writing-skills/references/examples
git mv brainstorming/spec-document-reviewer-prompt.md brainstorming/references/
git mv writing-plans/plan-document-reviewer-prompt.md writing-plans/references/
```

Files that move together into the same directory keep their intra-directory mentions valid; only mentions from SKILL.md files (still one level up) need fixing.

- [ ] **Step 2: Fix every mention**

Apply these exact substitutions:

1. `test-driven-development/SKILL.md`: `[writing-good-tests.md](writing-good-tests.md)` → `[writing-good-tests.md](references/writing-good-tests.md)`
2. `requesting-code-review/SKILL.md` (two occurrences): `[code-reviewer.md](code-reviewer.md)` → `[code-reviewer.md](references/code-reviewer.md)`
3. `subagent-driven-development/SKILL.md`: every occurrence of `../requesting-code-review/code-reviewer.md` → `../requesting-code-review/references/code-reviewer.md` (four occurrences: two inside the dot-graph labels, two in prose/links)
4. `subagent-driven-development/SKILL.md`: every link target `implementer-prompt.md`, `task-reviewer-prompt.md`, `re-review-prompt.md` → `references/<same name>` (find them with `grep -n "prompt.md" SKILL.md`; update link targets and backtick path mentions alike)
5. `systematic-debugging/SKILL.md`: `` See `root-cause-tracing.md` in this directory `` → `` See `references/root-cause-tracing.md` ``
6. `systematic-debugging/SKILL.md` closing list: `**`root-cause-tracing.md`**` → `**`references/root-cause-tracing.md`**`, `**`defense-in-depth.md`**` → `**`references/defense-in-depth.md`**`, `**`condition-based-waiting.md`**` → `**`references/condition-based-waiting.md`**`
7. `writing-skills/SKILL.md`: `see anthropic-best-practices.md` → `see references/anthropic-best-practices.md`; `` See `graphviz-conventions.dot` in this directory `` → `` See `references/graphviz-conventions.dot` ``; `` Use `render-graphs.js` in this directory `` → `` Use `references/render-graphs.js` ``; `./render-graphs.js ../some-skill` → `./references/render-graphs.js ../some-skill` (both usage lines); `See persuasion-principles.md for research foundation` → `See references/persuasion-principles.md for research foundation`; any link to `testing-skills-with-subagents.md` → `references/testing-skills-with-subagents.md`
8. Sweep for leftovers: `grep -rn "](writing-good-tests\|](code-reviewer\|](implementer-prompt\|](task-reviewer-prompt\|](re-review-prompt\|](testing-skills-with-subagents\|](spec-document-reviewer\|](plan-document-reviewer" plugins/dr-superpowers/skills/` — every hit must contain `references/`; fix any that don't, including in files this list missed.

- [ ] **Step 3: Verify**

Run: `node scripts/validate-repository.mjs` (60s timeout)
Expected: valid (the bundled-link check proves every markdown link resolves).
Run: `git status --short plugins/dr-superpowers/skills | grep -v "^R\|^ M\|^M"` — expected: no unexplained entries.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/skills
git commit -m "refactor(superpowers): move skill docs to references"
```

---

### Task 5: Move the sdd scripts to plugin `scripts/` and update path references

**Files:**
- Rename: `plugins/dr-superpowers/skills/subagent-driven-development/scripts/{sdd-workspace,task-brief,review-package}` → `plugins/dr-superpowers/scripts/`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md` and `references/{task-reviewer-prompt,re-review-prompt}.md`

**Interfaces:**
- Consumes: Task 4 (prompt files already under `references/`)
- Produces: the Contracts entry "script locations" — `scripts/sdd-workspace`, `scripts/task-brief`, `scripts/review-package` at the plugin root

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Move the three scripts together**

They resolve each other via `dirname "$0"` (task-brief and review-package call their sibling sdd-workspace), so they must stay siblings:

```bash
cd plugins/dr-superpowers
git mv skills/subagent-driven-development/scripts/sdd-workspace scripts/
git mv skills/subagent-driven-development/scripts/task-brief scripts/
git mv skills/subagent-driven-development/scripts/review-package scripts/
rmdir skills/subagent-driven-development/scripts
```

- [ ] **Step 2: Update the location wording**

In `skills/subagent-driven-development/SKILL.md`, the script mentions read `scripts/sdd-workspace PLAN_FILE`, `scripts/task-brief PLAN_FILE N`, `scripts/review-package PLAN_FILE BASE HEAD` — those spellings stay correct relative to the plugin root. What changes is the locator phrase: replace the one occurrence of

```
, from this skill's directory —
```

with

```
, from the plugin root (two levels above this skill's directory) —
```

Then run `grep -rn "skill's directory\|skill directory" plugins/dr-superpowers/skills/subagent-driven-development/` (covers the SKILL.md and the three prompt files) and rewrite any remaining phrase that locates the scripts in the skill directory to say the plugin root instead, keeping the `scripts/<name>` spellings unchanged.

- [ ] **Step 3: Smoke-test the moved scripts**

```bash
bash plugins/dr-superpowers/scripts/sdd-workspace docs/superpowers/plans/2026-09-11-dr-superpowers-standalone-base.md
```

Expected: prints an absolute path ending in `.superpowers/sdd/2026-09-11-dr-superpowers-standalone-base` and exits 0 (the workspace dir it creates is self-git-ignored; leave it).

```bash
bash plugins/dr-superpowers/scripts/task-brief docs/superpowers/plans/2026-09-11-dr-superpowers-standalone-base.md 1
```

Expected: exits 0 and prints a brief path whose file starts with `### Task 1:` (proves the sibling call works from the new location).

- [ ] **Step 4: Verify and commit**

Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid.

```bash
git add plugins/dr-superpowers
git commit -m "refactor(superpowers): move sdd scripts to plugin root"
```

---

### Task 6: Hook swap: SessionStart hook, session-start.sh, new hook.test.sh

**Files:**
- Create: `plugins/dr-superpowers/scripts/session-start.sh`
- Modify: `plugins/dr-superpowers/hooks/hooks.json` (full replacement)
- Modify: `plugins/dr-superpowers/tests/hook.test.sh` (full replacement)
- Delete: `plugins/dr-superpowers/scripts/tier-nudge.sh`

**Interfaces:**
- Consumes: `skills/using-superpowers/SKILL.md` (Task 2's routing lines are what the injection carries)
- Produces: the Contracts entries "Session record" and "Hook shape"

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4
**Approach:** inline - skip 3: the spec fixed the record path, format, and malformed-stdin behavior

- [ ] **Step 1: Write the failing test — replace `tests/hook.test.sh` with exactly:**

```bash
#!/usr/bin/env bash
# The SessionStart hook must inject the using-superpowers entry point in the
# Claude Code JSON shape, persist the session record keyed by sanitized cwd,
# tolerate malformed stdin (inject anyway, persist nothing), and always exit 0.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/session-start.sh"
HOOKS="$HERE/../hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

payload() {
  jq -n --arg tp '/tmp/fake-transcript.jsonl' --arg cwd 'D:\repo\example' \
    '{hook_event_name:"SessionStart",session_id:"s-123",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}

# --- well-formed stdin ---
HOME_A="$TMP/a"; mkdir -p "$HOME_A"
out=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null)
status=$?
check "well-formed: exits 0" "$status" "0"
check "well-formed: emits valid JSON" \
  "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "well-formed: event name is SessionStart" \
  "$(jq -r '.hookSpecificOutput.hookEventName // "MISSING"' <<<"$out" 2>/dev/null)" "SessionStart"
check "well-formed: additionalContext is non-empty" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "well-formed: context names the entry-point skill" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'dr-superpowers:using-superpowers')" "1"
check "well-formed: emits no permissionDecision" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"

RECORD="$HOME_A/.claude/dr-superpowers/sessions/D--repo-example.json"
check "well-formed: persists the session record" "$([ -f "$RECORD" ] && echo yes || echo no)" "yes"
check "record: transcript_path" \
  "$(jq -r '.transcript_path // "MISSING"' "$RECORD" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "record: session_id" "$(jq -r '.session_id // "MISSING"' "$RECORD" 2>/dev/null)" "s-123"
check "record: source" "$(jq -r '.source // "MISSING"' "$RECORD" 2>/dev/null)" "startup"
check "record: cwd" "$(jq -r '.cwd // "MISSING"' "$RECORD" 2>/dev/null)" 'D:\repo\example'

# --- malformed stdin ---
HOME_B="$TMP/b"; mkdir -p "$HOME_B"
out=$(printf 'not json' | HOME="$HOME_B" bash "$SCRIPT" 2>/dev/null)
status=$?
check "malformed: exits 0" "$status" "0"
check "malformed: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "malformed: persists nothing" \
  "$([ -d "$HOME_B/.claude" ] && echo yes || echo no)" "no"

# --- empty stdin ---
HOME_C="$TMP/c"; mkdir -p "$HOME_C"
out=$(printf '' | HOME="$HOME_C" bash "$SCRIPT" 2>/dev/null)
status=$?
check "empty: exits 0" "$status" "0"
check "empty: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"

# --- hooks.json wiring ---
check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hooks.json registers SessionStart with the full matcher" \
  "$(jq -r '.hooks.SessionStart[0].matcher // "MISSING"' "$HOOKS" 2>/dev/null)" "startup|resume|clear|compact"
check "hooks.json is synchronous" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].async // false' "$HOOKS" 2>/dev/null)" "false"
check "hooks.json forces the bash interpreter" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].shell // "MISSING"' "$HOOKS" 2>/dev/null)" "bash"
check "hooks.json has no PreToolUse entry" \
  "$(jq -r 'if .hooks.PreToolUse then "present" else "ABSENT" end' "$HOOKS" 2>/dev/null)" "ABSENT"
check "session-start.sh parses" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash plugins/dr-superpowers/tests/hook.test.sh` (120s timeout)
Expected: FAIL — `session-start.sh` does not exist and hooks.json still registers PreToolUse.

- [ ] **Step 3: Create `plugins/dr-superpowers/scripts/session-start.sh` with exactly:**

```bash
#!/usr/bin/env bash
# SessionStart hook: inject the using-superpowers entry point and persist the
# session's transcript path for the budget tooling. Injection must survive a
# missing jq or malformed stdin; only persistence is allowed to degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

stdin_json="$(cat 2>/dev/null || true)"

if command -v jq >/dev/null 2>&1 && [ -n "$stdin_json" ] \
   && jq -e . >/dev/null 2>&1 <<<"$stdin_json"; then
  session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
  transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
  cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
  source_event=$(jq -r '.source // empty' <<<"$stdin_json")
  if [ -n "$transcript_path" ] && [ -n "$cwd" ]; then
    sessions_dir="${HOME}/.claude/dr-superpowers/sessions"
    key=$(printf '%s' "$cwd" | tr -c 'A-Za-z0-9' '-')
    mkdir -p "$sessions_dir" 2>/dev/null \
      && jq -n --arg sid "$session_id" --arg tp "$transcript_path" \
            --arg cwd "$cwd" --arg src "$source_event" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{session_id:$sid,transcript_path:$tp,cwd:$cwd,source:$src,timestamp:$ts}' \
            > "${sessions_dir}/${key}.json" 2>/dev/null || true
  fi
fi

content="$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>/dev/null || true)"
[ -n "$content" ] || exit 0

# Escape for JSON embedding with bash parameter substitution (single C-level
# pass per character class; no jq dependency on the injection path).
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

escaped=$(escape_for_json "$content")
context="<EXTREMELY_IMPORTANT>\nYou have dr-superpowers.\n\n**Below is the full content of your 'dr-superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${escaped}\n</EXTREMELY_IMPORTANT>"

printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$context"
exit 0
```

- [ ] **Step 4: Replace `hooks/hooks.json` with exactly:**

```json
{
  "description": "Injects the dr-superpowers entry point at session start and persists the session's transcript path for budget tooling.",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh\"",
            "shell": "bash",
            "async": false
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Delete the tier-nudge**

```bash
git rm plugins/dr-superpowers/scripts/tier-nudge.sh
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash plugins/dr-superpowers/tests/hook.test.sh` (120s timeout)
Expected: all checks pass, `0 failed`.

- [ ] **Step 7: Verify repository-wide and commit**

Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid.

```bash
git add plugins/dr-superpowers
git commit -m "feat(superpowers): swap tier-nudge for SessionStart hook"
```

---

### Task 7: Manifests to 1.0.0 standalone; validator flip; layout test cases

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json` (full replacement)
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json` (full replacement)
- Modify: `.claude-plugin/marketplace.json`
- Modify: `scripts/validate-repository.mjs`
- Modify: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: the standalone manifest contract and the validator error strings `dr-superpowers: standalone plugin must not declare dependencies` and `claude: cross-marketplace dependency allowlist must be removed`

**Implementer:** dcc-superpower-companions:impl-opus-low
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Note on order: the manifest edits and the validator flip must land in the same task — between them the validator fails by design, so run nothing until Step 4.

- [ ] **Step 1: Replace `plugins/dr-superpowers/.claude-plugin/plugin.json` with exactly:**

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "dr-superpowers",
  "description": "Standalone fork of superpowers 6.3.0: brainstorming, planning, and tiered subagent execution with task scoring, explicit model and effort assignment, criteria-based review, and a Claude-hosted external Codex executor.",
  "version": "1.0.0",
  "author": {
    "name": "Darkraise"
  },
  "homepage": "https://github.com/darkraise/darkraise-ai-plugins/tree/main/plugins/dr-superpowers",
  "repository": "https://github.com/darkraise/darkraise-ai-plugins",
  "license": "MIT",
  "keywords": [
    "superpowers",
    "skills",
    "workflow",
    "tdd",
    "debugging",
    "planning",
    "subagents",
    "effort",
    "model-selection",
    "verification",
    "code-review",
    "codex",
    "external-executors"
  ]
}
```

- [ ] **Step 2: Replace `plugins/dr-superpowers/.codex-plugin/plugin.json` with exactly:**

```json
{
  "name": "dr-superpowers",
  "version": "1.0.0",
  "description": "Standalone fork of superpowers 6.3.0: brainstorming, planning, and tiered subagent execution with task scoring, explicit model and effort assignment, criteria-based review, and a Claude-hosted external Codex executor.",
  "author": {
    "name": "Darkraise"
  },
  "skills": "./skills/",
  "interface": {
    "shortDescription": "Standalone fork of superpowers 6.3.0 with task scoring, tiered dispatch, criteria-based review, and an external Codex executor.",
    "category": "Development",
    "displayName": "dr-superpowers",
    "developerName": "Darkraise"
  },
  "hooks": {}
}
```

- [ ] **Step 3: Edit `.claude-plugin/marketplace.json`**

Three changes:
1. `"version": "0.3.0"` → `"version": "0.4.0"`.
2. The `dr-superpowers` entry's `description` → the same new description as Step 1 (the long form).
3. Delete the entire `allowCrossMarketplaceDependenciesOn` property (the two-line array at the end of the file), leaving valid JSON.

- [ ] **Step 4: Flip the validator**

In `scripts/validate-repository.mjs`, replace:

```js
      if (client === 'claude' && entry.name === 'dr-superpowers') {
        const dependency = manifest.dependencies?.find(d => d.name === 'superpowers');
        if (!dependency?.marketplace || !catalog.allowCrossMarketplaceDependenciesOn?.includes(dependency.marketplace)) errors.push('dr-superpowers: required Superpowers dependency/allowlist missing');
      }
```

with:

```js
      if (client === 'claude' && entry.name === 'dr-superpowers' && manifest.dependencies?.length) {
        errors.push('dr-superpowers: standalone plugin must not declare dependencies');
      }
```

and, directly after the existing line `if (catalog.name !== 'darkraise') errors.push(...)`, insert:

```js
    if (client === 'claude' && catalog.allowCrossMarketplaceDependenciesOn !== undefined) errors.push('claude: cross-marketplace dependency allowlist must be removed');
```

- [ ] **Step 5: Add the layout test cases**

In `tests/repository-layout.test.mjs`, append to the array of rejection cases (after the `'missing bundled reference'` entry):

```js
    ['reintroduced dependency', c => { c.dependencies = [{ name: 'superpowers', marketplace: 'claude-plugins-official' }]; }, /must not declare dependencies/, 'plugins/dr-superpowers/.claude-plugin/plugin.json'],
    ['reintroduced allowlist', c => { c.allowCrossMarketplaceDependenciesOn = ['claude-plugins-official']; }, /allowlist/],
```

- [ ] **Step 6: Run the tests**

Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid.
Run: `node --test tests/repository-layout.test.mjs` (120s timeout) — expected: all pass, including the two new subtests.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin plugins/dr-superpowers/.codex-plugin .claude-plugin/marketplace.json scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "feat(superpowers)!: standalone manifests at 1.0.0"
```

---

### Task 8: Stray-reference check in the validator

**Files:**
- Modify: `scripts/validate-repository.mjs`
- Modify: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: Task 3's rename (the repository must already be clean) and Task 6's tier-nudge deletion
- Produces: the validator error string `<path>:<line>: legacy plugin-name reference`, with `plugins/dr-superpowers/reference/legacy-names.md` reserved as the one allowed location

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Append to the rejection-case array in `tests/repository-layout.test.mjs` (after Task 7's entries):

```js
    ['legacy name reference', (c, dir) => { writeFileSync(resolve(dir, 'plugins/dr-superpowers/reference/stray.md'), 'superpowers:brainstorming\n'); }, /legacy plugin-name reference/],
```

- [ ] **Step 2: Run it to verify it fails**

Run: `node --test tests/repository-layout.test.mjs` (120s timeout)
Expected: the `legacy name reference` subtest FAILS (the validator emits no such error yet); all others pass.

- [ ] **Step 3: Implement the check**

In `scripts/validate-repository.mjs`, insert before the final `return errors;` (after the existing bundled-link loop):

```js
  const legacyPattern = /(?<!dr-)superpowers:|dcc-superpower-companions:/;
  const legacyAllowed = new Set(['plugins/dr-superpowers/reference/legacy-names.md']);
  for (const name of names) {
    const pluginRoot = resolve(root, 'plugins', name);
    if (!existsSync(pluginRoot)) continue;
    const visit = dir => {
      for (const item of readdirSync(dir, { withFileTypes: true })) {
        const path = resolve(dir, item.name);
        if (item.isDirectory()) { visit(path); continue; }
        const rel = relative(root, path).replaceAll('\\', '/');
        if (legacyAllowed.has(rel)) continue;
        readFileSync(path, 'utf8').split('\n').forEach((line, index) => {
          if (legacyPattern.test(line)) errors.push(`${rel}:${index + 1}: legacy plugin-name reference`);
        });
      }
    };
    visit(pluginRoot);
  }
```

The lookbehind lets `dr-superpowers:` through while catching bare `superpowers:`; `dcc-superpower-companions:` is caught whole (it does not contain the substring `superpowers:`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/repository-layout.test.mjs` (120s timeout) — expected: all pass.
Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid (proves the real tree has no stray prefix; if this fails, the listed file:line locations are Task 3 leftovers — fix them with the same rename rules, never by widening `legacyAllowed`).

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "feat(superpowers): add legacy-prefix stray check"
```

---

### Task 9: README migration section, hook rewrite, LICENSES/

**Files:**
- Modify: `plugins/dr-superpowers/README.md`
- Create: `plugins/dr-superpowers/LICENSES/superpowers-LICENSE`
- Create: `plugins/dr-superpowers/LICENSES/andrej-karpathy-skills-LICENSE`

**Interfaces:**
- Consumes: Task 3's rename (README is already `dr-superpowers:`-prefixed) and Task 6's hook swap
- Produces: the migration instructions and license files the spec §7 requires

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 0 = 2

- [ ] **Step 1: Fix the garbled legacy-translation sentence**

Task 3's sweep turned the old `dcc-superpower-companions:` mention into `dr-superpowers:`, garbling the sentence. In `README.md`, replace:

```
Claude translates known legacy
`dr-superpowers:` agent names at read time; disable the old plugin
before enabling this one. Original assignments and evaluations remain intact.
```

with:

```
Claude translates known legacy agent names from the dcc-superpower-companions
era at read time; disable that plugin before enabling this one. Original
assignments and evaluations remain intact.
```

- [ ] **Step 2: Reword the fork line**

Replace:

```
Extends [superpowers](https://github.com/obra/superpowers) so that every task in
an implementation plan records which implementer subagent runs it, chosen from a
grid of model and reasoning-effort pairings.
```

with:

```
A standalone fork of [superpowers](https://github.com/obra/superpowers) 6.3.0
(MIT — see `LICENSES/`) that also records, for every task in an implementation
plan, which implementer subagent runs it, chosen from a grid of model and
reasoning-effort pairings.
```

- [ ] **Step 3: Replace the Requirements first paragraph**

Replace the paragraph that begins `**superpowers must be installed.**` and ends `Missing prerequisites must be resolved before execution.` (post-rename it reads `dr-superpowers:verification-before-completion` inside) with:

```
**The superpowers workflow ships in-plugin.** The fork carries the full skill
set — brainstorming through finishing-a-development-branch — frozen at upstream
6.3.0, so no other plugin is required: every agent definition preloads
`dr-superpowers:verification-before-completion` through its `skills:`
frontmatter, and the assigning and dispatching skills use the plugin's own
`scripts/sdd-workspace`, `task-brief`, and `review-package`. Disable the
upstream `superpowers` plugin: same-named skills in two enabled plugins can
double-trigger.
```

- [ ] **Step 4: Update the lenient-hook sentence**

In the `**Bash, jq, Git, and GNU timeout/coreutils.**` paragraph, replace:

```
The
hook is the lenient case: without `jq` it degrades to a silent no-op, and
`bash` is required for it to run at all.
```

with:

```
The
SessionStart hook is the lenient case: without `jq` it still injects the entry
point and only skips persisting the session record, and `bash` is required for
it to run at all.
```

(Keep the rest of the paragraph — the `"shell": "bash"` explanation still holds.)

- [ ] **Step 5: Replace the "How it fires" section**

Replace the entire `## How it fires` section body (three paragraphs, from `A `PreToolUse` hook on the `Skill` tool` — post-rename wording — through `which is correct rather than broken.`) with:

```
A `SessionStart` hook (matcher `startup|resume|clear|compact`) injects the
`dr-superpowers:using-superpowers` entry point as `additionalContext`, so every
session starts with the skill-routing rules — including the pointers to
`selecting-approaches`, `assigning-implementers`, and
`dispatching-tiered-implementers` that a PreToolUse nudge used to add. The same
script persists the session's `transcript_path`, `session_id`, `cwd`, and
`source` to `~/.claude/dr-superpowers/sessions/<sanitized-cwd>.json` (last
writer wins per directory); the session-budget tooling of a later release reads
it. Malformed stdin skips persistence but never blocks the injection, and the
hook always exits 0.
```

- [ ] **Step 6: Add the migration section**

Insert after the `## How it fires` section:

```
## Migrating from 0.x

1.0.0 is standalone and breaking. On a machine with the old setup:

1. **Re-point the marketplace.** The `darkraise` marketplace registration in
   `~/.claude/settings.json` may still name `darkraise/claude-code-plugins`;
   the canonical repository is `darkraise/darkraise-ai-plugins`. Remove and
   re-add the marketplace (or edit the registration) to point there.
2. **Statusline.** `dcc-statusline` is `dr-status` in this catalog; enable
   `dr-status@darkraise` and disable the old name.
3. **Telegram notifications.** `dcc-telegram-notify` is not in this catalog;
   keep it installed from its previous source or drop it.
4. **Disable the superseded plugins:** `superpowers` (its skills now ship
   here), `dcc-superpower-companions` (folded into this plugin), and
   `andrej-karpathy-skills` (its guidelines are folded into the skills where
   they fire).
```

- [ ] **Step 7: Add the Licenses section**

Insert before the `## Tests` section:

```
## Licenses

MIT. `LICENSES/` carries the licenses of the forked and folded projects:
[superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT),
frozen at 6.3.0 with no upstream sync, and
[andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)
(MIT).
```

- [ ] **Step 8: Create the license files**

```bash
mkdir -p plugins/dr-superpowers/LICENSES
cp "$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/LICENSE" \
   plugins/dr-superpowers/LICENSES/superpowers-LICENSE
```

Create `plugins/dr-superpowers/LICENSES/andrej-karpathy-skills-LICENSE` with exactly:

```
MIT License

Copyright (c) 2025 forrestchang (andrej-karpathy-skills)

The andrej-karpathy-skills repository declares MIT in its README without
shipping a license file; this is the standard MIT text for that grant.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 9: Verify**

Run: `node scripts/validate-repository.mjs` (60s timeout) — expected: valid (README passed the stray check; the license files carry no colon-prefixed names).
Run: `grep -n "PreToolUse\|tier-nudge" plugins/dr-superpowers/README.md` — expected: at most the historical mention "a PreToolUse nudge used to add" from Step 5; nothing describing a live hook.

- [ ] **Step 10: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/LICENSES
git commit -m "docs(superpowers): migration guide and licenses"
```

---

### Task 10: Full verification sweep

**Files:** none modified — this task only runs the spec §8 gates and reports.

**Interfaces:**
- Consumes: everything
- Produces: the verification record for the ledger

**Implementer:** dcc-superpower-companions:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Repository validator**

Run: `node scripts/validate-repository.mjs` (60s timeout)
Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 2: Full test suite**

Run: `node scripts/test-all.mjs` (it bounds and kills its own children; allow up to 15 minutes)
Expected: every suite passes — validator, `tests/*.test.mjs`, dr-status suite, and all `plugins/dr-superpowers/tests/*.test.sh` including the new `hook.test.sh`.

- [ ] **Step 3: Plugin validation**

Run each with a 120s timeout:

```bash
claude plugin validate .
claude plugin validate plugins/dr-superpowers
claude plugin validate plugins/dr-status
claude plugin validate plugins/dcc-darkraise-ui
claude plugin validate plugins/dcc-darkraise-win32ui
```

Expected: each reports valid. If `claude` is missing from PATH, report BLOCKED rather than skipping.

- [ ] **Step 4: Process hygiene and working-tree check**

Confirm nothing started by this task or earlier tasks is still running (`jobs`, and check for stray `node`/`bash` children you spawned). Run `git status --short` — expected: only `?? plugins/darkmem-resume/` (owner's live work, untouched) plus the git-ignored `.superpowers/` workspace.

- [ ] **Step 5: Record results**

Write the pass/fail of Steps 1–4 into the ledger checkpoint for this task. No commit.
