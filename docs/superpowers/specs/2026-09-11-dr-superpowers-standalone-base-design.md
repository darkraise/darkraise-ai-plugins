# dr-superpowers 1.0.0 — standalone base (sub-project 1 design)

Date: 2026-09-11. Status: approved design for sub-project 1 of the program design
`2026-09-11-dr-superpowers-fork-design.md` (§6 item 1). Scope rule: behaviour unchanged
except where this spec says otherwise; folding, budget, planning, and inline-mode work
belong to sub-projects 2–5.

Approach: inline — skip 3: the program design already chose the shape; remaining choices
are mechanical.

## 1. Decisions fixed here

- **Canonical remote** (owner, 2026-09-11): `darkraise/darkraise-ai-plugins`. Plugin
  manifest homepage/repository fields and the migration README use it; the installed
  marketplace registration (`darkraise/claude-code-plugins` in `~/.claude/settings.json`)
  is re-pointed by the user per the migration README.
- **Copy source**: the installed upstream cache
  `~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/`.
- **Target layout now, not later**: sub-project 1 adopts the §4 target shape for
  everything it copies (per-skill `references/`, sdd scripts in plugin `scripts/`), so
  later sub-projects never move files.

## 2. Skills copied from upstream (13)

All upstream skills except `dispatching-parallel-agents`:

using-superpowers, brainstorming, writing-plans, executing-plans,
subagent-driven-development, test-driven-development, systematic-debugging,
verification-before-completion, requesting-code-review, receiving-code-review,
finishing-a-development-branch, using-git-worktrees, writing-skills.

Wording and layout fixes applied during the copy:

- Every `superpowers:` skill reference becomes `dr-superpowers:`.
- **brainstorming** drops the visual companion: the `scripts/` server
  (frame-template.html, helper.js, server.cjs, start-server.sh, stop-server.sh),
  `visual-companion.md`, the checklist item that offers it, and the Visual Companion
  section. A one-line note points to the Artifact tool for visual questions on Claude.
- **using-superpowers** keeps only the Codex row of the platform table and
  `references/codex-tools.md`; the pi, antigravity, hermes and gemini reference files
  and rows are dropped. Its routing guidance names the three companion skills
  (selecting-approaches during brainstorming, assigning-implementers during
  writing-plans, dispatching-tiered-implementers during subagent-driven-development) —
  this replaces the deleted tier-nudge hook (§5).
- Any reference to `dispatching-parallel-agents` (subagent-driven-development,
  selecting-approaches, others found at plan time) is replaced with direct Agent-tool
  wording: dispatch independent agents in one message so they run concurrently.
- Supporting documents move to `skills/<name>/references/` with links fixed
  (e.g. writing-plans/plan-document-reviewer-prompt.md, systematic-debugging's
  companion docs, TDD's writing-good-tests.md, requesting-code-review/code-reviewer.md,
  subagent-driven-development's prompt files, writing-skills' companion docs).
- The sdd helper scripts `sdd-workspace`, `task-brief`, `review-package` move to
  `plugins/dr-superpowers/scripts/`, with subagent-driven-development's path references
  updated.
- Upstream skill-eval fixtures are dropped unless a SKILL.md links them:
  systematic-debugging's CREATION-LOG.md, test-academic.md, test-pressure-{1,2,3}.md;
  audited file-by-file at plan time. The bundled-link validator catches mistakes.
- Upstream repo-level files (AGENTS.md, CLAUDE.md, GEMINI.md, host adapters, docs,
  release notes, tests, assets, package.json) are not copied.

## 3. Existing content: rename only

- The three existing skills (assigning-implementers, dispatching-tiered-implementers,
  selecting-approaches), all 19 agents, and `reference/*.md` get a mechanical rename of
  `superpowers:` and `dcc-superpower-companions:` prefixes to `dr-superpowers:`. Agent
  frontmatter preloads included (`skills: - dr-superpowers:verification-before-completion`).
- No restructuring; folding is sub-project 2. Codex-lane scripts, criteria files, and
  their tests are untouched.

## 4. Hook swap

Deleted: the PreToolUse tier-nudge — `scripts/tier-nudge.sh`, its `hooks.json` entry,
and `tests/hook.test.sh` (replaced, §6).

New `hooks/hooks.json`: SessionStart only, matcher `startup|resume|clear|compact`,
command `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-start.sh"`, `"shell": "bash"`,
`"async": false` — the repo's existing hook pattern, not upstream's `run-hook.cmd`
polyglot, since hooks are Claude-only now.

`scripts/session-start.sh`:

- Reads the hook's stdin JSON (`session_id`, `transcript_path`, `cwd`, `source`).
- Emits `hookSpecificOutput.additionalContext` containing the
  dr-superpowers:using-superpowers SKILL.md content (upstream behaviour; Claude Code
  format only — no Cursor/Copilot branches).
- Persists `{session_id, transcript_path, cwd, source, timestamp}` to
  `~/.claude/dr-superpowers/sessions/<sanitized-cwd>.json` — sanitized-cwd is the cwd
  with non-alphanumerics replaced by `-` (collision-tolerant: last writer wins per
  directory). User-level so repositories are never polluted. Sub-project 3's
  `context-size` reads this file; the format is a contract from this sub-project on.
- Exits 0 on malformed stdin and emits nothing (a hook must never break session start).
- No dependency on `CLAUDE_CODE_SESSION_ID`.

The ≤1.2k-token entry-point rewrite (program design R12) is later work; sub-project 1
injects the adapted using-superpowers content as upstream did.

## 5. Manifests

- `.claude-plugin/plugin.json`: version 1.0.0; `dependencies` removed; description
  updated to reflect the full workflow fork; homepage
  `https://github.com/darkraise/darkraise-ai-plugins/tree/main/plugins/dr-superpowers`,
  repository `https://github.com/darkraise/darkraise-ai-plugins`; keywords extended
  (tdd, debugging, planning, workflow).
- `.codex-plugin/plugin.json`: version 1.0.0; same description; keeps
  `"skills": "./skills/"` and `"hooks": {}`.
- `.claude-plugin/marketplace.json`: `allowCrossMarketplaceDependenciesOn` removed;
  dr-superpowers description updated to match; marketplace version 0.3.0 → 0.4.0.
- `.agents/plugins/marketplace.json`: unchanged (no version or dependency fields).
- Other plugins' manifests untouched — repo rule: do not enroll unrelated plugin
  directories during public-name migrations.

## 6. Validator and tests

- `scripts/validate-repository.mjs` (currently lines 47–50) flips: error if the Claude
  dr-superpowers manifest declares any `dependencies`, or if the Claude catalog has
  `allowCrossMarketplaceDependenciesOn`.
- New stray-reference check in the same validator: scan the four maintained plugin
  directories (`plugins/{dr-superpowers,dr-status,dcc-darkraise-ui,dcc-darkraise-win32ui}`)
  for `superpowers:` or `dcc-superpower-companions:` prefixes; excluded:
  `docs/superpowers/**` (outside the scan anyway) and the reserved translation table
  `plugins/dr-superpowers/reference/legacy-names.md`, named now so sub-project 2 lands
  without a validator change.
- `tests/repository-layout.test.mjs`: add rejection cases asserting that a reintroduced
  `dependencies` entry or allowlist errors, and one for the stray-reference check;
  existing cases (hooks, versions, sources, bundled links) stay valid.
- `plugins/dr-superpowers/tests/hook.test.sh`: replaced. New coverage: session-start.sh
  emits valid JSON in the Claude shape; additionalContext non-empty and contains the
  entry-point marker; persists transcript_path from a synthetic stdin payload (HOME
  overridden to a temp dir); malformed stdin exits 0 and emits nothing; hooks.json
  registers SessionStart with matcher `startup|resume|clear|compact`, `shell: bash`,
  `async: false`, and no PreToolUse. Crib from upstream `tests/hooks/test-session-start.sh`.
- `scripts/test-all.mjs`: no change — it globs `*.test.sh`.

## 7. Migration README and LICENSES

`plugins/dr-superpowers/README.md` gains a "Migrating from 0.x" section:

- Re-point the `darkraise` marketplace registration from `darkraise/claude-code-plugins`
  to `darkraise/darkraise-ai-plugins`.
- `dcc-statusline` → `dr-status`.
- `dcc-telegram-notify` is not in this catalog; keep it from its old source or drop it.
- Disable `superpowers`, `dcc-superpower-companions`, and `andrej-karpathy-skills`
  (avoids the same-name double-trigger risk; program design §8).

`plugins/dr-superpowers/LICENSES/`: both MIT texts — superpowers (Jesse Vincent) copied
from the upstream cache LICENSE; andrej-karpathy-skills (forrestchang) from its installed
cache. README gains a short attribution note.

## 8. Verification

Program design §7 as written: `node scripts/validate-repository.mjs`,
`node scripts/test-all.mjs`, `claude plugin validate` on the marketplace and every
Claude plugin; bounded timeouts; every started process cleaned up.

## 9. Out of scope

Folding companion skills and `{#scope}`/schema/translation-table content (sub-project 2);
context-size, repo-audit, handoff, resume-execution, session-budget.md (3); plan header
block, plan-lint, plan review, amendments (4); executing-plans rewrite (5). The
`plugins/darkmem-resume/` directory is the owner's live work: never touched or committed.

## 10. Risks

- Between sub-projects 1 and 2 the companion skills are triggered only by the injected
  routing text and their own descriptions (the tier-nudge is gone). Accepted: the
  sub-projects are sequential.
- Whether Codex auto-triggers the newly copied skills from descriptions alone is
  unverified (program design §8); nothing in this sub-project depends on it.
- The `~/.claude/dr-superpowers/sessions/` format is consumed by sub-project 3; changing
  it later means changing both sides in one sub-project.
