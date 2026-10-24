# dforge:ui-ux Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `dforge:ui-ux` skill: a UI/UX contract written at design time, carried into every UI task, and proven in the running UI behind a gate that blocks the final review, finishing and every "done" claim.

**Architecture:** One sourced library (`scripts/lib/ui-ux.sh`) owns every rule about UI files, fingerprints, contracts and proof reports; `scripts/ui-proof` exposes it as a CLI whose `check` verb is the gate, and `scripts/ui-lint` holds the edit-time patterns. Two hooks (PostToolUse lint and reminder, a Stop hold), plan-lint, task-brief and lens-route consume the library; the skill, its references and edits to six existing skills and references put the process in front of the agent.

**Tech Stack:** bash, awk (POSIX, mawk-safe), git, jq, markdown; Playwright MCP for the walkthrough.

**Spec:** `docs/dforge/specs/2026-10-24-ui-ux-skill-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — three of nineteen tasks are heavy (Tasks 10, 13 and 14, total 5) and are delegated; every other task totals 4 or less

**Parallelism:** sequential — the spec's strategy: one chain in which hooks and gates call the scripts and the skill edits cite both

**Plan review:** 2026-10-24 — dforge:judge-opus — executability 15 / coherence 14 / coverage 15 / assumptions 14 (round 1)

## Global Constraints

- All code changes are under `plugins/dforge/` in this repository; never edit the installed copy under `/root/.claude/plugins/cache/`. `<plugin-root>` in commands below means the dforge root the session's entry point prints (`Plugin root: …`); scripts this plan creates are run from the repository copy, `plugins/dforge/scripts/…`.
- Commit as `Darkraise <quangtc94@gmail.com>`. No `Co-Authored-By`, `Claude-Session`, "Generated with" or other AI attribution in any commit. Subjects follow `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Every test, git and CLI command runs under `timeout`; test suites run as `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/<name>.test.sh` from the repository root. Leave no process running: close every browser, kill every server, tmux session and emulator you start, and confirm with `ps` before a task ends.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Shell code must run under bash 3.2+ and Git Bash on Windows CI: no awk interval expressions (`{m,n}`; the host awk is mawk 1.3.4), no `grep -P`, no `sha256sum`, no `mapfile`; expand a possibly empty array as `${a[@]+"${a[@]}"}`; split rows that may hold empty cells on `\037`, never on a tab.
- Files under `plugins/dforge/criteria/` are ASCII only (`tests/criteria.test.sh` checks it): no em dashes or curly quotes there.
- `plugins/dforge/skills/using-dforge/SKILL.md` stays at most 5100 bytes (`tests/hook.test.sh`).
- Lint fixtures never carry a `.ts`, `.tsx`, `.js` or `.jsx` extension in the repository: `tsc -p plugins/dforge` type-checks everything under `tests/`. They are stored as `*.fixture` and copied to their real extension inside the test's temporary directory.
- `node scripts/validate-repository.mjs` resolves every `dforge:<name>` written in `plugins/dforge/`: no file may name `dforge:ui-ux` before Task 8 creates the skill directory.
- Do not edit `docs/superpowers/`, historical plans or specs. The spec is read-only except where a task says otherwise.
- New executable scripts (`scripts/ui-proof`, `scripts/ui-lint`) are committed with mode 100755, like `scripts/plan-lint`; hook scripts (`*.sh`) and libraries with 100644, like `scripts/turn-end.sh`.
- macOS and iOS are out of scope: no task adds a guide or a check for them.

## Contracts

- **`scripts/lib/ui-ux.sh`** (sourced; sources `lib/plan.sh` unless `plan_header` is already defined). Globs are bash case patterns matched against repository-relative paths, so `*` crosses `/`.
  - `UIUX_DEFAULT_GLOBS`, `UIUX_EXCLUDE_GLOBS` — the platform defaults and the exclusions (`*.test.* *.spec.* *.stories.*`).
  - `uiux_profile ROOT` → `<docs>/ui-ux/profile.md` (path printed whether or not it exists).
  - `uiux_proofs_dir ROOT` → `<docs>/ui-ux/proofs`.
  - `uiux_field FILE LABEL` → the value of FILE's first `**LABEL:**` line outside fences, trimmed, backticks removed.
  - `uiux_globs ROOT` → effective globs, one per line: the profile's `**UI paths:**` value, else the defaults.
  - `uiux_is_ui PATH GLOBS` → status 0 when PATH matches a glob in GLOBS (newline-separated) and no exclusion.
  - `uiux_filter ROOT` → the UI paths among the paths on stdin.
  - `uiux_files ROOT` → every existing UI file, tracked or untracked but not ignored, sorted.
  - `uiux_changed ROOT BASE` → UI files differing between BASE and the working tree (committed or not, deleted included) plus untracked UI files.
  - `uiux_fingerprint ROOT` → 16 lowercase hex digits over the paths and contents of `uiux_files`, or `none`.
  - `uiux_section FILE HEADING` → the lines of `## HEADING` up to the next `## ` heading (fenced lines included, fence-aware).
  - `uiux_ids` → item IDs defined in the text on stdin, in order, unique: a `- **ID**` bullet or a `| ID |` table row at column 0, outside fences.
  - `uiux_contract_ids SPEC` → `uiux_section SPEC "UI/UX contract" | uiux_ids`.
  - `uiux_items FILE SECTION ID...` → each ID's definition verbatim, each followed by one blank line: a bullet with its continuation lines (indented two spaces or a tab), or a table row printed under its table's header and separator rows.
  - `uiux_rows REPORT` → one `ID\037verdict\037evidence\037note` line per `## Results` table row whose first cell is an ID; the verdict lower-cased.
  - `uiux_ran_skill TRANSCRIPT` → status 0 when the transcript shows a Skill tool call for `dforge:ui-ux` or `ui-ux`, or a typed `/dforge:ui-ux` command.
- **`scripts/ui-proof`** — `paths | fingerprint | changed --base REF | contract SPEC [ID...] | stamp REPORT | check --base REF [--spec SPEC] [--active]`, run inside the checkout. `check` prints `ui-proof: ok — …` and exits 0, or prints one `ui-proof: FAIL <step>: <what>` line per failure (steps `report`, `scope`, `freshness`, `coverage`, `verdicts`, `evidence`, `judge`) then `ui-proof: report <path>` when a report was chosen, and exits 1; usage errors exit 2.
- **Profile** `<docs>/ui-ux/profile.md` — labels `**Platform:**`, `**Harness:**`, `**UI test runner:**` (a command, or `none`), `**UI paths:**`, `**Design system:**`, `**Token paths:**`, `**Viewports:**`, `**Themes:**`, `**Users:**`, `**Voice:**`, `**Screenshots:**` (`local` or `commit`), then `## Decisions`.
- **Contract** — spec section `## UI/UX contract`; first line `**UI/UX depth:** <touch|feature|product> — <why>`; parts `### UI`, `### UX`, `### Output promise`; items `- **UI-<n>** — …` / `- **UX-<n>** — …` / `- **OP-<n>** — …` or table rows `| OP-<n> | … |`.
- **Proof report** `<docs>/ui-ux/proofs/<YYYY-MM-DD>-<slug>.md` — header labels `**Contract:**` (a spec path, or `touch`), `**Platform:**`, `**Viewports:**`, `**Themes:**`, `**Evidence:**` (`local` or `committed`), `**Fingerprint:**`, `**Judge:** <ship|fix> <fingerprint> — <judge file>`, optional `**Accepted by:** "<the user's words>"`; a touch report's `## Delta` section; a `## Results` table `| ID | Verdict | Evidence | Note |` with verdicts `pass`, `deviation` (note starts `cites:`), `fail`, `unverifiable`. Judge file `<same name>.judge.md`, the judge's reply verbatim, last line `Verdict: <ship|fix> <fingerprint>`.
- **`scripts/ui-lint FILE...`** — prints `<file>:<line>: <rule> <message>`; exit 0 no finding, 1 findings, 2 usage. Rules: `raw-color`, `outline-removed`, `click-non-interactive`, `img-alt`, `transition-all`, `zoom-disabled`, `tabindex-positive`, `paste-blocked`, `xaml-hardcoded-brush`, `android-hardcoded-color`, `android-hardcoded-text`, `android-image-description`.
- **Hooks** — `scripts/ui-edit-hook.sh` (PostToolUse, matcher `Edit|Write|MultiEdit`, timeout 30) prints nothing or `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":…}}`; its reminder line contains `Load dforge:ui-ux`. `scripts/ui-turn-end.sh` (third entry of `Stop[0].hooks`, timeout 60) prints nothing or `{"decision":"block","reason":…,"systemMessage":"dforge held the stop: …"}`; the pending line it honours is `UI proof: pending — <why>`.
- **Plan line** `**UI/UX:** <IDs>` on a task, checked by plan-lint; task-brief appends `## UI/UX contract items`.
- **Lens** id `ui-ux`, `Applies: ui-paths`; lens-route prints `reason=ui-paths`.
- **Task 1 note** `docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md` — what Playwright MCP did with an absolute worktree path and a bare filename.

## Assumptions (evidence)

- A `dforge:impl-sonnet-low` subagent loaded the deferred `mcp__playwright__*` tools, drove a page, took a screenshot and the session's Read tool displayed it (probe, 2026-10-24). A screenshot path outside `/root/repositories/darkraise-ai-plugins` was refused ("outside allowed roots"); a bare filename landed in the primary checkout's root, not a worktree. Whether an absolute path into a worktree under `.worktrees/` is accepted is unverified — Task 1 verifies it.
- `tsc` covers `plugins/dforge/tests` (`plugins/dforge/.claude-plugin/types/tsconfig.json` `include`, read 2026-10-24), hence the `.fixture` constraint.
- The host awk is `mawk 1.3.4 20250131` (`awk --version`, 2026-10-24); interval expressions are avoided for it and for older CI awks.
- `plugins/dforge/skills/using-dforge/SKILL.md` is 5089 bytes (`wc -c`, 2026-10-24) against the 5100 cap in `tests/hook.test.sh`; Task 15's three trims save 42 bytes and its row adds 48, ending at 5095 (computed on a copy, 2026-10-24).
- `scripts/lens-route` orders lenses security, silent-failures, test-quality, `lang-*`, type-design, docs-comments, others (`scripts/lens-route:49-56`) with a default cap of 4 (`:95`); `tests/criteria.test.sh` pins the lens list and the `Applies:` clause grammar.
- `scripts/lib/turn-refs.sh` writes `<common dir>`, `<worktree top>`, then `<commit>\t<worktree path>` per branch; `scripts/turn-start.sh` stores it as `<stamp>.refs` per session.
- `scripts/auto-run --session SID pending` exits 0 when a run is bound to SID (printing `none` or the action) and 3 when none is (`scripts/auto-run:47,74`).
- `scripts/test-all.mjs` runs every `plugins/dforge/tests/*.test.sh`, so new suites need no registration (read 2026-10-24).
- Codex lane: `codex-gate` printed `usable=false reason=setting review=false lane=false` (2026-10-24), so the plan is Claude-only: codex off — setting.
- The run's register `docs/dforge/registers/2026-10-24-ui-ux-skill-auto.md` holds no rows, so no task carries an `**Items:**` line.
- The probe's subagent listed these Playwright MCP tools (2026-10-24): browser_click, browser_close, browser_console_messages, browser_drag, browser_drop, browser_evaluate, browser_file_upload, browser_fill_form, browser_find, browser_handle_dialog, browser_hover, browser_navigate, browser_navigate_back, browser_network_request, browser_network_requests, browser_press_key, browser_resize, browser_run_code_unsafe, browser_select_option, browser_snapshot, browser_tabs, browser_take_screenshot, browser_type, browser_wait_for. It exercised navigate, resize, press_key, snapshot, take_screenshot and close; the others are named in `platforms/web.md` from that listing.
- `ui-proof check` binds a report to a spec by its `**Contract:**` path and needs a judge line at every depth, so it never reads the depth line: the spec's `**UI/UX depth:**` only selects the judge seat (the walkthrough's §The judge), which is why the report never declares a depth the gate trusts.
- `plugins/dforge/tests/darkmem-sync/hooks.test.mjs:181-188` pins `Stop[0].hooks` to exactly two entries; Task 10 extends that assertion with the third.
- Demo statements A2, A3 and the Windows half of A17 need the owner (a fresh interactive session, a Windows machine); finishing lists every `demo` statement for the owner (`skills/finishing-a-development-branch/SKILL.md:62`). Task 18 runs the demos this host can: A20 and the terminal half of A17.

## Task index

1. Verify Playwright MCP writes into a worktree
2. Add the ui-ux library and ui-proof read commands
3. Add ui-proof stamp and the check gate
4. Add ui-lint with per-rule fixtures
5. Add the UI proof judge criteria
6. Write the contract, state and interaction references
7. Write the walkthrough and platform guides
8. Write the ui-ux skill
9. Add the PostToolUse lint and reminder hook
10. Add the Stop hold for unproven UI changes
11. Teach plan-lint the UI/UX line
12. Append contract items to UI task briefs
13. Add the ui-ux review lens
14. Gate the final review, finishing and done claims
15. Route UI work to the skill
16. Document the UI/UX line for plans and seats
17. Describe the skill in the README and manifests
18. Run the walkthrough and terminal demos
19. Validate the repository and pressure-test the skill

---

### Task 1: Verify Playwright MCP writes into a worktree

**Files:**
- Create: `docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md`

**Interfaces:**
- Consumes: None
- Produces: the Task 1 note (Contracts)

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

Run this in the execution worktree (the checkout whose `git rev-parse --show-toplevel` is under `.worktrees/`). It verifies the spec's riskiest assumption for worktrees.

- [ ] **Step 1: Prepare the evidence directory**

```bash
WT=$(git rev-parse --show-toplevel); echo "$WT"
mkdir -p "$WT/.dforge/ui-ux/probe"
ls -a "$WT/.dforge" | grep -c '^.gitignore$'   # expect 1; if 0: printf '*\n' > "$WT/.dforge/.gitignore"
if [ -d /root/repositories/darkraise-ai-plugins/.playwright-mcp ]; then echo yes; else echo no; fi > "$WT/.dforge/pw-preexisting"
cat "$WT/.dforge/pw-preexisting"   # no: the probe may create it, and Step 5 removes it
```

- [ ] **Step 2: Probe with an absolute worktree path**

Load `mcp__playwright__browser_navigate`, `mcp__playwright__browser_take_screenshot` and `mcp__playwright__browser_close` with ToolSearch. Navigate to `data:text/html,<button>Probe</button>`. Take a screenshot with `filename` set to the absolute path `$WT/.dforge/ui-ux/probe/abs.png` (the value Step 1 printed, written out). Record the tool's reply verbatim. Then run `ls -l "$WT/.dforge/ui-ux/probe/abs.png"`.

- [ ] **Step 3: Probe with a bare filename**

Take a second screenshot with `filename` set to `bare-probe.png`. Record the path the tool reports, then find the file: `ls -l "$WT/bare-probe.png" /root/repositories/darkraise-ai-plugins/bare-probe.png 2>&1`. Close the browser.

- [ ] **Step 4: Write the note**

Create `docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md`:

```markdown
# Playwright MCP and worktree evidence paths

Probe run 2026-10-24 in the execution worktree `<WT>`.

- **Absolute worktree path:** <written to <path> | refused: "<error text>">
- **Bare filename:** <landed at <path>>
- **Snapshot files:** <where the tool wrote page snapshots, or none>

The walkthrough (`plugins/dforge/skills/ui-ux/references/walkthrough.md`) saves
screenshots by absolute path into `<checkout>/.dforge/ui-ux/<slug>/` and, when
the tool refuses that path, by bare filename and then moves the file.
```

Fill each `<…>` with what Steps 2-3 observed.

- [ ] **Step 5: Clean up and commit**

```bash
WT=$(git rev-parse --show-toplevel)
rm -rf "$WT/.dforge/ui-ux/probe" "$WT/bare-probe.png" /root/repositories/darkraise-ai-plugins/bare-probe.png "$WT/.playwright-mcp"
if [ "$(cat "$WT/.dforge/pw-preexisting")" = no ]; then rm -rf /root/repositories/darkraise-ai-plugins/.playwright-mcp; fi
rm -f "$WT/.dforge/pw-preexisting"
git status --short    # expect only the note
git add docs/dforge/notes/2026-10-24-ui-ux-playwright-worktree.md
git commit -m "docs(notes): record the Playwright worktree probe"
```

---

### Task 2: Add the ui-ux library and ui-proof read commands

**Files:**
- Create: `plugins/dforge/scripts/lib/ui-ux.sh`
- Create: `plugins/dforge/scripts/ui-proof`
- Test: `plugins/dforge/tests/ui-proof.test.sh`

**Interfaces:**
- Consumes: None
- Produces: `scripts/lib/ui-ux.sh` and the `paths`, `fingerprint`, `changed`, `contract` verbs of `scripts/ui-proof` (Contracts)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/ui-proof.test.sh` (Task 3 appends its gate cases before the summary lines):

````bash
#!/usr/bin/env bash
# ui-proof is the ui-ux skill's gate: which files are UI files, their
# fingerprint, a spec's contract, and the check that blocks finishing until a
# proof report covers the current UI. Every case runs in a throwaway repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$HERE/../scripts/ui-proof"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.email t@example.com && git config user.name t
mkdir -p src
printf 'export const App = () => null;\n' > src/App.tsx
printf '# readme\n' > README.md
git add . && git commit -q -m base
BASE=$(git rev-parse HEAD)
up() { bash "$UP" "$@"; }

# --- paths ---
check "paths: the defaults hold the web globs" "$(up paths | grep -cxF '*.tsx')" "1"
check "paths: the defaults hold the windows globs" "$(up paths | grep -cxF '*.xaml')" "1"
check "paths: no bare *.ts" "$(up paths | grep -cxF '*.ts')" "0"
mkdir -p docs/dforge/ui-ux
printf '# UI profile\n\n**Platform:** web\n**UI paths:** `src/ui/*` `*.tsx`\n' > docs/dforge/ui-ux/profile.md
check "paths: the profile's globs replace the defaults" "$(up paths | tr '\n' ' ')" "src/ui/* *.tsx "
rm docs/dforge/ui-ux/profile.md

# --- fingerprint ---
fp1=$(up fingerprint)
check "fingerprint: 16 hex digits" "$(grep -cE '^[0-9a-f]{16}$' <<<"$fp1")" "1"
check "fingerprint: stable" "$(up fingerprint)" "$fp1"
printf 'readme 2\n' >> README.md
check "fingerprint: a non-UI edit leaves it" "$(up fingerprint)" "$fp1"
git checkout -q README.md
printf '// edit\n' >> src/App.tsx
check "fingerprint: an uncommitted UI edit changes it" "$([ "$(up fingerprint)" != "$fp1" ] && echo yes || echo no)" "yes"
git checkout -q src/App.tsx
printf 'a {}\n' > src/new.css
check "fingerprint: an untracked UI file changes it" "$([ "$(up fingerprint)" != "$fp1" ] && echo yes || echo no)" "yes"
rm src/new.css
printf 'x\n' > src/a.test.tsx
check "fingerprint: a test file is not a UI file" "$(up fingerprint)" "$fp1"
rm src/a.test.tsx
mkdir -p "$TMP/empty" && (cd "$TMP/empty" && git init -q && bash "$UP" fingerprint) > "$TMP/fp-empty"
check "fingerprint: none without UI files" "$(cat "$TMP/fp-empty")" "none"

# --- changed ---
printf '// v2\n' >> src/App.tsx
printf 'b {}\n' > src/b.css
check "changed: uncommitted and untracked UI files" "$(up changed --base HEAD | tr '\n' ' ')" "src/App.tsx src/b.css "
rm src/b.css; git checkout -q src/App.tsx
up changed >/dev/null 2>&1; check "changed: --base is required" "$?" "2"

# --- contract ---
mkdir -p docs/dforge/specs
cat > docs/dforge/specs/s.md <<'EOF'
# Spec

## UI/UX contract

**UI/UX depth:** feature — a settings screen

### UI

- **UI-1** — Settings layout.
  Board: default, error.
- **UI-2** — Tokens only.

### UX

- **UX-1** — Escape closes the dialog.

```markdown
- **UX-9** — an example, not an item
```

### Output promise

| ID | Promise |
|---|---|
| OP-1 | Matches the boards. |

## Acceptance

- **UX-7** — outside the section
EOF
check "contract: the ids in order, fences and other sections skipped" "$(up contract docs/dforge/specs/s.md | tr '\n' ' ')" "UI-1 UI-2 UX-1 OP-1 "
check "contract: a bullet item with its continuation" "$(up contract docs/dforge/specs/s.md UI-1)" $'- **UI-1** — Settings layout.\n  Board: default, error.'
check "contract: a table item under its header" "$(up contract docs/dforge/specs/s.md OP-1)" $'| ID | Promise |\n|---|---|\n| OP-1 | Matches the boards. |'
check "contract: an unknown id prints nothing" "$(up contract docs/dforge/specs/s.md UX-5)" ""
up contract docs/dforge/specs/missing.md >/dev/null 2>&1; check "contract: a missing spec exits 2" "$?" "2"
up nope >/dev/null 2>&1; check "usage: an unknown verb exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: FAIL lines (the script does not exist yet), exit 1.

- [ ] **Step 3: Write the library**

Create `plugins/dforge/scripts/lib/ui-ux.sh`:

````bash
# Sourced. The ui-ux skill's shared parsing: which files are UI files, the
# fingerprint of their contents, the project UI profile, a spec's UI/UX
# contract and a proof report's rows. Globs are bash case patterns matched
# against repository-relative paths, so * crosses /.
declare -F plan_header >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/plan.sh"

UIUX_DEFAULT_GLOBS='*.tsx *.jsx *.vue *.svelte *.astro *.html *.css *.scss *.sass *.less *.xaml *.axaml *.rc *.Designer.cs *.razor *.cshtml *res/layout/*.xml *res/values/*.xml *res/drawable/*.xml *.ui *.qml *.glade *.blp'
UIUX_EXCLUDE_GLOBS='*.test.* *.spec.* *.stories.*'

# uiux_profile ROOT — ROOT's UI profile path, whether or not it exists.
uiux_profile() { printf '%s/ui-ux/profile.md\n' "$(dforge_docs_root "$1")"; }

# uiux_proofs_dir ROOT — where ROOT's proof reports live.
uiux_proofs_dir() { printf '%s/ui-ux/proofs\n' "$(dforge_docs_root "$1")"; }

# uiux_field FILE LABEL — the value of FILE's first "**LABEL:**" line outside
# fences, trimmed, backticks removed; nothing when there is none.
uiux_field() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    index($0, p) == 1 {
      v = substr($0, length(p) + 1); gsub(/`/, "", v)
      sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      print v; stop = 1
    }
  '
}

# uiux_globs ROOT — the effective UI globs, one per line: the profile's
# "**UI paths:**" value when it has one, else the platform defaults.
uiux_globs() {
  local profile line=""
  profile=$(uiux_profile "$1")
  [ ! -f "$profile" ] || line=$(uiux_field "$profile" "UI paths")
  [ -n "$line" ] || line=$UIUX_DEFAULT_GLOBS
  tr ' \t,' '\n\n\n' <<<"$line" | grep -v '^$'
}

# uiux_is_ui PATH GLOBS — status 0 when PATH matches one of GLOBS (one per
# line) and none of the exclusions.
uiux_is_ui() {
  local path=$1 glob
  set -f
  for glob in $UIUX_EXCLUDE_GLOBS; do
    # shellcheck disable=SC2254
    case $path in $glob) set +f; return 1 ;; esac
  done
  set +f
  while IFS= read -r glob; do
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254
    case $path in $glob) return 0 ;; esac
  done <<<"$2"
  return 1
}

# uiux_filter ROOT — the UI paths among the repository-relative paths on stdin.
uiux_filter() {
  local globs path
  globs=$(uiux_globs "$1")
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if uiux_is_ui "$path" "$globs"; then printf '%s\n' "$path"; fi
  done
  return 0
}

# uiux_files ROOT — every UI file in ROOT's working tree, tracked or
# untracked but not ignored, sorted; a tracked file deleted from the tree is
# left out.
uiux_files() {
  local path
  git -C "$1" ls-files -co --exclude-standard 2>/dev/null | LC_ALL=C sort -u | uiux_filter "$1" |
    while IFS= read -r path; do
      if [ -f "$1/$path" ]; then printf '%s\n' "$path"; fi
    done
  return 0
}

# uiux_changed ROOT BASE — the UI files that differ between BASE and the
# working tree, committed or not, deleted ones included, plus untracked ones.
uiux_changed() {
  { git -C "$1" diff --name-only "$2" -- 2>/dev/null
    git -C "$1" ls-files -o --exclude-standard 2>/dev/null; } | LC_ALL=C sort -u | uiux_filter "$1"
}

# uiux_fingerprint ROOT — 16 hex digits naming the paths and contents of every
# UI file, or "none" when there is none. Git does the hashing.
uiux_fingerprint() {
  local files hashes
  files=$(uiux_files "$1")
  if [ -z "$files" ]; then echo none; return 0; fi
  hashes=$(cd "$1" && printf '%s\n' "$files" | git hash-object --stdin-paths) || return 1
  paste <(printf '%s\n' "$files") <(printf '%s\n' "$hashes") | git -C "$1" hash-object --stdin | cut -c1-16
}

# uiux_section FILE HEADING — FILE's "## HEADING" section up to the next "## "
# heading, fenced lines included; a "## " line inside a fence does not end it.
uiux_section() {
  tr -d '\r' < "$1" | awk -v h="## $2" "$_PLAN_AWK"'
    in_fence($0) { if (on) print; next }
    /^## / { t = $0; sub(/[ \t]+$/, "", t); on = (t == h); next }
    on { print }
  '
}

# uiux_ids — the item IDs the text on stdin defines, in order, unique: a
# "- **ID**" bullet or a "| ID |" table row at column 0, outside fences.
uiux_ids() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    match($0, /^- \*\*(UI|UX|OP)-[0-9]+\*\*/) {
      id = substr($0, 5, RLENGTH - 6); if (!seen[id]++) print id; next
    }
    match($0, /^\|[ \t]*(UI|UX|OP)-[0-9]+[ \t]*\|/) {
      id = substr($0, RSTART, RLENGTH); gsub(/[| \t]/, "", id); if (!seen[id]++) print id
    }
  '
}

# uiux_contract_ids SPEC — the IDs the spec's "## UI/UX contract" defines.
uiux_contract_ids() { uiux_section "$1" "UI/UX contract" | uiux_ids; }

# uiux_items FILE SECTION ID... — each ID's definition in FILE's section,
# verbatim, in the order given, each followed by a blank line: a bullet with
# its continuation lines (indented by two spaces or a tab), or a table row
# under its table's header and separator rows.
uiux_items() {
  local file=$1 section=$2 text id
  shift 2
  text=$(uiux_section "$file" "$section")
  for id in "$@"; do
    awk -v id="$id" "$_PLAN_AWK"'
      in_fence($0) { if (on) print; next }
      on && /^(  |\t)/ { print; next }
      on { on = 0 }
      /^\|/ { if (!intable) { head = $0; sepl = ""; rows = 0; intable = 1 } rows++; if (rows == 2) sepl = $0 }
      !/^\|/ { intable = 0 }
      index($0, "- **" id "**") == 1 { print; on = 1; next }
      match($0, /^\|[ \t]*(UI|UX|OP)-[0-9]+[ \t]*\|/) {
        c = substr($0, RSTART, RLENGTH); gsub(/[| \t]/, "", c)
        if (c == id) { print head; print sepl; print }
      }
    ' <<<"$text"
    echo
  done
}

# uiux_rows REPORT — one "ID\037verdict\037evidence\037note" line per row of
# the report's "## Results" table whose first cell is an ID.
uiux_rows() {
  uiux_section "$1" Results | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^\|/ {
      n = split($0, c, "|")
      id = c[2]; gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id !~ /^(UI|UX|OP)-[0-9]+$/) next
      for (i = 3; i <= 5; i++) { v[i] = (i < n ? c[i] : ""); gsub(/^[ \t]+|[ \t]+$/, "", v[i]) }
      printf "%s\037%s\037%s\037%s\n", id, tolower(v[3]), v[4], v[5]
    }
  '
}

# uiux_ran_skill TRANSCRIPT — status 0 when the transcript shows a Skill tool
# call for dforge:ui-ux (or ui-ux) or a typed /dforge:ui-ux command.
uiux_ran_skill() {
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  jq -rR 'fromjson? | objects
    | if .type? == "assistant" then
        .message.content? | arrays | .[] | select(.type? == "tool_use" and .name? == "Skill")
        | .input.skill? | strings | select(. == "dforge:ui-ux" or . == "ui-ux")
      elif .type? == "user" then
        .message.content? | (if type == "string" then . elif type == "array" then (.[] | select(.type? == "text") | .text?) else empty end)
        | strings | select(contains("<command-name>/dforge:ui-ux"))
      else empty end' "$1" 2>/dev/null | grep -q .
}
````

- [ ] **Step 4: Write the CLI's read verbs**

Create `plugins/dforge/scripts/ui-proof` (Task 3 replaces the `stamp|check)` placeholder arm):

````bash
#!/usr/bin/env bash
# The ui-ux skill's proof tool: which files are UI files, their fingerprint, a
# spec's contract items, stamping a proof report, and the gate that blocks the
# final review, finishing and a "done" claim until the UI is proven.
#
# Usage: ui-proof paths | fingerprint | changed --base REF
#        ui-proof contract SPEC [ID...]
#        ui-proof stamp REPORT
#        ui-proof check --base REF [--spec SPEC] [--active]
# Run inside the checkout; paths print repository-relative.
# check: exit 0 when the gate is off (no profile, no contract, no --active), no
# UI file differs from REF, or a proof report passes every step; otherwise one
# "ui-proof: FAIL <step>: <what>" line per failure and exit 1. Usage: exit 2.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/ui-ux.sh"

die() { printf 'ui-proof: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: ui-proof paths | fingerprint | changed --base REF | contract SPEC [ID...] | stamp REPORT | check --base REF [--spec SPEC] [--active]"; }

[ $# -ge 1 ] || usage
root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git checkout"
dforge_stores_init "$root"
cmd=$1; shift

base="" spec="" active=0
parse_args() {
  while [ $# -gt 0 ]; do
    case $1 in
      --base) [ $# -ge 2 ] || usage; base=$2; shift 2 ;;
      --spec) [ $# -ge 2 ] || usage; spec=$2; shift 2 ;;
      --active) active=1; shift ;;
      *) usage ;;
    esac
  done
  [ -n "$base" ] || usage
  git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "bad --base: $base"
}

case $cmd in
  paths) [ $# -eq 0 ] || usage; uiux_globs "$root" ;;
  fingerprint) [ $# -eq 0 ] || usage; uiux_fingerprint "$root" ;;
  changed) parse_args "$@"; uiux_changed "$root" "$base" ;;
  contract)
    [ $# -ge 1 ] || usage
    f=$(dforge_resolve "$1" "$root"); shift
    [ -f "$f" ] || die "no such spec: $f"
    if [ $# -eq 0 ]; then uiux_contract_ids "$f"; else uiux_items "$f" "UI/UX contract" "$@"; fi ;;
  stamp|check) die "$cmd: not implemented yet" ;;
  *) usage ;;
esac
````

Then: `chmod +x plugins/dforge/scripts/ui-proof`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: every line `ok`, the summary `N passed, 0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/lib/ui-ux.sh plugins/dforge/scripts/ui-proof plugins/dforge/tests/ui-proof.test.sh
git commit -m "feat(dforge): add the ui-ux library and ui-proof"
```

---

### Task 3: Add ui-proof stamp and the check gate

**Files:**
- Modify: `plugins/dforge/scripts/ui-proof`
- Test: `plugins/dforge/tests/ui-proof.test.sh`

**Interfaces:**
- Consumes: `scripts/lib/ui-ux.sh` (Contracts)
- Produces: `ui-proof stamp` and `ui-proof check` (Contracts)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/ui-proof.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- check: the gate ---
up check >/dev/null 2>&1; check "check: --base is required" "$?" "2"
out=$(up check --base HEAD); st=$?
check "check: gate off without a profile or a contract" "$st" "0"
check "check: says the gate is off" "$(grep -c 'gate off' <<<"$out")" "1"
printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
git add docs && git commit -q -m docs
check "check: no UI change since the base passes" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"
printf '// v2\n' >> src/App.tsx
out=$(up check --base HEAD); st=$?
check "check: an uncommitted UI change with no report fails" "$st" "1"
check "check: names the missing report" "$(grep -c '^ui-proof: FAIL report:' <<<"$out")" "1"
check "check: names the changed file" "$(grep -c 'src/App.tsx' <<<"$out")" "1"
git commit -q -am 'ui v2'
check "check: a committed UI change with no report fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"

PROOFS=docs/dforge/ui-ux/proofs
mkdir -p "$PROOFS" .dforge/ui-ux/t
printf '*\n' > .dforge/.gitignore
printf 'png' > .dforge/ui-ux/t/a.png
report() { # report <name> <contract> <rows> [extra header line]
  { printf '# UI proof: t\n\n**Contract:** %s\n**Platform:** web\n**Evidence:** local\n%s\n' "$2" "${4:-}"
    if [ "$2" = touch ]; then printf '\n## Delta\n\n**UI/UX depth:** touch — a fix\n\n- **UX-1** — the fix\n'; fi
    printf '\n## Results\n\n| ID | Verdict | Evidence | Note |\n|---|---|---|---|\n%s\n' "$3"
  } > "$PROOFS/$1.md"
}
judge() { # judge <name> <verdict> — the judge file and the report's Judge line
  local fp; fp=$(up fingerprint)
  printf 'The proof holds.\n\nVerdict: %s %s\n' "$2" "$fp" > "$PROOFS/$1.judge.md"
  printf '\n**Judge:** %s %s — %s/%s.judge.md\n' "$2" "$fp" "$PROOFS" "$1" >> "$PROOFS/$1.md"
}
PASSROW='| UX-1 | pass | .dforge/ui-ux/t/a.png | |'
report 2026-10-24-t touch "$PASSROW"
out=$(up stamp "$PROOFS/2026-10-24-t.md")
check "stamp: reports the fingerprint" "$(grep -c "^ui-proof: stamped $(up fingerprint)" <<<"$out")" "1"
check "stamp: writes one fingerprint line under Contract" "$(grep -A1 '^\*\*Contract:\*\*' "$PROOFS/2026-10-24-t.md" | grep -c '^\*\*Fingerprint:\*\*')" "1"
judge 2026-10-24-t ship
out=$(up check --base "$BASE"); st=$?
check "check: a stamped, judged touch report passes" "$st" "0"
check "check: says ok" "$(grep -c '^ui-proof: ok' <<<"$out")" "1"
up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
check "stamp: keeps a judge line for the current fingerprint" "$(grep -c '^\*\*Judge:\*\*' "$PROOFS/2026-10-24-t.md")" "1"
check "stamp: never duplicates the fingerprint line" "$(grep -c '^\*\*Fingerprint:\*\*' "$PROOFS/2026-10-24-t.md")" "1"

printf '// v3\n' >> src/App.tsx
out=$(up check --base "$BASE"); st=$?
check "check: a UI edit after the stamp fails" "$st" "1"
check "check: names the stale report" "$(grep -c '^ui-proof: FAIL freshness:' <<<"$out")" "1"
up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
check "stamp: a judge line for another fingerprint is removed" "$(grep -c '^\*\*Judge:\*\*' "$PROOFS/2026-10-24-t.md")" "0"
out=$(up check --base "$BASE"); st=$?
check "check: no judge line fails" "$st" "1"
check "check: names the judge step" "$(grep -c '^ui-proof: FAIL judge:' <<<"$out")" "1"
judge 2026-10-24-t ship
check "check: judged again, it passes" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"

try() { # try <rows> [extra header line] [judge verdict] — a fresh touch report; prints check's status
  rm -f "$PROOFS"/2026-10-24-t.*
  report 2026-10-24-t touch "$1" "${2:-}"
  up stamp "$PROOFS/2026-10-24-t.md" >/dev/null
  judge 2026-10-24-t "${3:-ship}"
  up check --base "$BASE" >/dev/null; echo "$?"
}
check "verdicts: a fail row fails" "$(try '| UX-1 | fail | .dforge/ui-ux/t/a.png | the dialog stays open |')" "1"
check "verdicts: an uncited deviation fails" "$(try '| UX-1 | deviation | .dforge/ui-ux/t/a.png | looks better |')" "1"
check "verdicts: a cited deviation passes" "$(try '| UX-1 | deviation | .dforge/ui-ux/t/a.png | cites: user answer 2026-10-24 |')" "0"
check "verdicts: a pass row without evidence fails" "$(try '| UX-1 | pass | - | |')" "1"
check "verdicts: a missing screenshot fails" "$(try '| UX-1 | pass | .dforge/ui-ux/t/missing.png | |')" "1"
check "verdicts: a test name is evidence" "$(try '| UX-1 | pass | A12: escape closes the dialog | |')" "0"
check "verdicts: unverifiable without acceptance fails" "$(try '| UX-1 | unverifiable | - | no emulator here |')" "1"
check "verdicts: unverifiable with the user's acceptance passes" "$(try '| UX-1 | unverifiable | - | no emulator here |' '**Accepted by:** "ship it without the Android run"')" "0"
check "verdicts: an unknown verdict fails" "$(try '| UX-1 | ok | .dforge/ui-ux/t/a.png | |')" "1"
check "coverage: a delta item with no row fails" "$(try '| UX-2 | pass | .dforge/ui-ux/t/a.png | |')" "1"
check "judge: a fix verdict fails" "$(try "$PASSROW" '' fix)" "1"
try "$PASSROW" >/dev/null
rm "$PROOFS/2026-10-24-t.judge.md"
check "judge: a missing judge file fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"
try "$PASSROW" >/dev/null
printf 'Verdict: fix %s\n' "$(up fingerprint)" > "$PROOFS/2026-10-24-t.judge.md"
check "judge: a judge file whose verdict differs fails" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"

# --- a spec with a contract binds the report ---
try "$PASSROW" >/dev/null
out=$(up check --base "$BASE" --spec docs/dforge/specs/s.md); st=$?
check "spec: a touch report does not prove a spec with a contract" "$st" "1"
check "spec: says no report names the spec" "$(grep -c '^ui-proof: FAIL report:' <<<"$out")" "1"
rm -f "$PROOFS"/2026-10-24-t.*
cp docs/dforge/specs/s.md docs/dforge/specs/other.md
ROWS='| UI-1 | pass | .dforge/ui-ux/t/a.png | |
| UI-2 | pass | .dforge/ui-ux/t/a.png | |
| UX-1 | pass | .dforge/ui-ux/t/a.png | |
| OP-1 | pass | .dforge/ui-ux/t/a.png | |'
report 2026-10-24-o docs/dforge/specs/other.md "$ROWS"; up stamp "$PROOFS/2026-10-24-o.md" >/dev/null; judge 2026-10-24-o ship
check "spec: a report bound to another spec does not count" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "1"
rm -f "$PROOFS"/2026-10-24-o.*
report 2026-10-24-s docs/dforge/specs/s.md "$(head -n 3 <<<"$ROWS")"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
out=$(up check --base "$BASE" --spec docs/dforge/specs/s.md); st=$?
check "spec: a contract ID with no row fails" "$st" "1"
check "spec: names the missing ID" "$(grep -c 'FAIL coverage: OP-1' <<<"$out")" "1"
check "spec: coverage applies without --spec too" "$(up check --base "$BASE" >/dev/null; echo $?)" "1"
report 2026-10-24-s docs/dforge/specs/s.md "$ROWS"; up stamp "$PROOFS/2026-10-24-s.md" >/dev/null; judge 2026-10-24-s ship
check "spec: a full report bound to the spec passes" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "0"
rm docs/dforge/ui-ux/profile.md
check "active: a spec with a contract turns the gate on" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "0"
rm -f "$PROOFS"/*.md
check "active: a spec with a contract and no report fails" "$(up check --base "$BASE" --spec docs/dforge/specs/s.md >/dev/null; echo $?)" "1"
check "active: --active turns the gate on without a profile" "$(up check --base "$BASE" --active >/dev/null; echo $?)" "1"
check "active: without it, no profile and no spec, the gate is off" "$(up check --base "$BASE" >/dev/null; echo $?)" "0"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: most new cases FAIL (`stamp: not implemented yet`; the `--base is required` case already passes), exit 1.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/ui-proof`, replace the line `  stamp|check) die "$cmd: not implemented yet" ;;` with:

````bash
  stamp)
    [ $# -eq 1 ] || usage
    report=$1
    [ -f "$report" ] || die "no such report: $report"
    grep -q '^\*\*Contract:\*\*' "$report" || die "the report has no **Contract:** line to stamp beside"
    fp=$(uiux_fingerprint "$root") || die "cannot fingerprint the UI files"
    has=0
    if grep -q '^\*\*Fingerprint:\*\*' "$report"; then has=1; fi
    tmp=$(mktemp) || die "mktemp failed"
    # A judge line for another fingerprint judged other code: drop it, so an
    # edit after the verdict needs a new verdict.
    tr -d '\r' < "$report" | awk -v fp="$fp" -v has="$has" "$_PLAN_AWK"'
      in_fence($0) { print; next }
      index($0, "**Fingerprint:**") == 1 { print "**Fingerprint:** " fp; next }
      index($0, "**Judge:**") == 1 {
        v = substr($0, 11); sub(/^[ \t]+/, "", v); split(v, w, /[ \t]+/)
        if (w[2] != fp) next
      }
      { print }
      !has && !put && index($0, "**Contract:**") == 1 { print "**Fingerprint:** " fp; put = 1 }
    ' > "$tmp" && cat "$tmp" > "$report"
    rm -f "$tmp"
    printf 'ui-proof: stamped %s in %s\n' "$fp" "$report" ;;
  check)
    parse_args "$@"
    spec_bound=""
    if [ -n "$spec" ]; then
      spec_file=$(dforge_resolve "$spec" "$root")
      [ -f "$spec_file" ] || die "no such spec: $spec"
      [ -z "$(uiux_contract_ids "$spec_file")" ] || spec_bound=$spec_file
    fi
    if [ "$active" = 0 ] && [ ! -f "$(uiux_profile "$root")" ] && [ -z "$spec_bound" ]; then
      echo "ui-proof: ok — gate off (no UI profile, no UI/UX contract)"
      exit 0
    fi
    changed=$(uiux_changed "$root" "$base")
    if [ -z "$changed" ]; then
      echo "ui-proof: ok — no UI file differs from $base"
      exit 0
    fi
    fp=$(uiux_fingerprint "$root") || die "cannot fingerprint the UI files"
    fails=()
    failed() { fails+=("$1: $2"); }
    dir=$(uiux_proofs_dir "$root")
    report="" newest=""
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      if [ -n "$spec_bound" ]; then
        rc=$(uiux_field "$r" Contract)
        [ -n "$rc" ] && [ "$(dforge_resolve "$rc" "$root")" = "$spec_bound" ] || continue
      fi
      newest=$r
      if [ "$(uiux_field "$r" Fingerprint)" = "$fp" ]; then report=$r; fi
    done < <(ls "$dir"/*.md 2>/dev/null | grep -v '\.judge\.md$' | LC_ALL=C sort)
    if [ -z "$report" ]; then
      if [ -n "$newest" ]; then
        failed freshness "$(dforge_name "$newest" "$root") was stamped at $(uiux_field "$newest" Fingerprint); the UI files are now at $fp"
      else
        failed report "no proof report under $(dforge_name "$dir" "$root")${spec_bound:+ names $spec}"
      fi
      failed scope "UI files changed since $base: $(head -n 10 <<<"$changed" | tr '\n' ' ')"
    else
      rc=$(uiux_field "$report" Contract)
      if [ "$rc" = touch ]; then
        want=$(uiux_section "$report" Delta | uiux_ids)
        [ -n "$want" ] || failed coverage "the touch report has no ## Delta items"
      else
        cf=$(dforge_resolve "$rc" "$root")
        want=""
        if [ -f "$cf" ]; then
          want=$(uiux_contract_ids "$cf")
          [ -n "$want" ] || failed coverage "$rc has no ## UI/UX contract items"
        else
          failed coverage "the report's contract $rc does not exist"
        fi
      fi
      rows=$(uiux_rows "$report")
      for id in $want; do
        grep -q "^$id"$'\037' <<<"$rows" || failed coverage "$id has no row in ## Results"
      done
      accepted=$(uiux_field "$report" "Accepted by")
      while IFS=$'\037' read -r id verdict ev note; do
        [ -n "$id" ] || continue
        case $verdict in
          pass|deviation)
            if [ -z "$ev" ] || [ "$ev" = - ]; then failed evidence "$id is $verdict with no evidence"; fi
            if [ "$verdict" = deviation ] && ! [[ "$note" =~ ^[Cc]ites:[[:space:]]*[^[:space:]] ]]; then
              failed verdicts "$id is a deviation whose note does not start with \"cites:\" and its reason"
            fi
            IFS=',' read -r -a items <<<"$ev"
            for item in ${items[@]+"${items[@]}"}; do
              item=$(sed -e 's/^[[:space:]`]*//' -e 's/[[:space:]`]*$//' <<<"$item")
              case $item in
                *.png|*.jpg|*.jpeg|*.webp|*.gif)
                  [ -f "$root/$item" ] || [ -f "$item" ] || failed evidence "$id cites $item, which does not exist" ;;
              esac
            done ;;
          fail) failed verdicts "$id failed: ${note:-no note}" ;;
          unverifiable) [ -n "$accepted" ] || failed verdicts "$id is unverifiable and the report has no **Accepted by:** line quoting the user" ;;
          *) failed verdicts "$id has the unknown verdict \"$verdict\" (pass, deviation, fail or unverifiable)" ;;
        esac
      done <<<"$rows"
      judge=$(uiux_field "$report" Judge)
      if [ -z "$judge" ]; then
        failed judge "no **Judge:** line; dispatch the judge seat (references/walkthrough.md)"
      else
        jv=$(awk '{ print $1 }' <<<"$judge")
        jfp=$(awk '{ print $2 }' <<<"$judge")
        jfile=$(sed -E 's/^[^ ]+ +[^ ]+ +(—|-) +//' <<<"$judge")
        if [ "$jv" != ship ]; then
          failed judge "the judge said $jv"
        elif [ "$jfp" != "$fp" ]; then
          failed judge "the verdict is for $jfp; the UI files are at $fp; judge again"
        else
          jpath=$(dforge_resolve "$jfile" "$root")
          if [ ! -f "$jpath" ]; then
            failed judge "the judge file $jfile does not exist"
          else
            last=$(tr -d '\r' < "$jpath" | sed '/^[[:space:]]*$/d' | tail -n 1 | sed 's/[[:space:]]*$//')
            [ "$last" = "Verdict: ship $fp" ] || failed judge "$jfile does not end with \"Verdict: ship $fp\""
          fi
        fi
      fi
    fi
    if [ ${#fails[@]} -eq 0 ]; then
      printf 'ui-proof: ok — %s proves the UI at %s\n' "$(dforge_name "$report" "$root")" "$fp"
      exit 0
    fi
    for f in "${fails[@]}"; do printf 'ui-proof: FAIL %s\n' "$f"; done
    [ -z "$report" ] || printf 'ui-proof: report %s\n' "$(dforge_name "$report" "$root")"
    exit 1 ;;
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: `N passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/ui-proof plugins/dforge/tests/ui-proof.test.sh
git commit -m "feat(dforge): gate UI work on ui-proof check"
```

---

### Task 4: Add ui-lint with per-rule fixtures

**Files:**
- Create: `plugins/dforge/scripts/ui-lint`
- Create: `plugins/dforge/tests/fixtures/ui-lint/<rule>.<bad|good>.<ext>.fixture` (24 files, one shape)
- Test: `plugins/dforge/tests/ui-lint.test.sh`

**Interfaces:**
- Consumes: None
- Produces: `scripts/ui-lint` (Contracts)

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the fixtures**

Create each file below under `plugins/dforge/tests/fixtures/ui-lint/` with exactly the content shown (one line each unless shown otherwise), ending in a newline:

| File | Content |
|---|---|
| `raw-color.bad.tsx.fixture` | `<div style={{ color: '#ff0000' }}>Error</div>` |
| `raw-color.good.tsx.fixture` | `<a href="#add" className="text-destructive">Add</a>` |
| `outline-removed.bad.css.fixture` | `button:focus { outline: none; }` |
| `outline-removed.good.css.fixture` | two lines: `button:focus { outline: none; }` and `button:focus-visible { outline: 2px solid var(--ring); }` |
| `click-non-interactive.bad.tsx.fixture` | `<div onClick={open}>Open</div>` |
| `click-non-interactive.good.tsx.fixture` | `<div role="button" tabIndex={0} onClick={open} onKeyDown={onKey}>Open</div>` |
| `img-alt.bad.tsx.fixture` | `<img src="a.png" />` |
| `img-alt.good.tsx.fixture` | `<img src="a.png" alt="Profile photo" />` |
| `transition-all.bad.css.fixture` | `.card { transition: all 200ms ease; }` |
| `transition-all.good.css.fixture` | `.card { transition: transform 200ms ease, opacity 200ms ease; }` |
| `zoom-disabled.bad.html.fixture` | `<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">` |
| `zoom-disabled.good.html.fixture` | `<meta name="viewport" content="width=device-width, initial-scale=1">` |
| `tabindex-positive.bad.tsx.fixture` | `<input tabIndex={2} />` |
| `tabindex-positive.good.tsx.fixture` | `<input tabIndex={-1} />` |
| `paste-blocked.bad.tsx.fixture` | `<input onPaste={e => e.preventDefault()} />` |
| `paste-blocked.good.tsx.fixture` | `<input onPaste={trackPaste} />` |
| `xaml-hardcoded-brush.bad.xaml.fixture` | `<TextBlock Foreground="#FF0000" Text="Error" />` |
| `xaml-hardcoded-brush.good.xaml.fixture` | `<TextBlock Foreground="{ThemeResource SystemErrorTextColor}" Text="Error" />` |
| `android-hardcoded-color.bad.xml.fixture` | `<TextView android:textColor="#FF0000" android:text="@string/error" />` |
| `android-hardcoded-color.good.xml.fixture` | `<TextView android:textColor="@color/error" android:text="@string/error" />` |
| `android-hardcoded-text.bad.xml.fixture` | `<TextView android:text="Save" />` |
| `android-hardcoded-text.good.xml.fixture` | `<TextView android:text="@string/save" />` |
| `android-image-description.bad.xml.fixture` | two lines: `<ImageView` and `    android:src="@drawable/logo" />` |
| `android-image-description.good.xml.fixture` | three lines: `<ImageView`, `    android:src="@drawable/logo"`, `    android:contentDescription="@string/logo" />` |

- [ ] **Step 2: Write the failing test**

Create `plugins/dforge/tests/ui-lint.test.sh`:

````bash
#!/usr/bin/env bash
# ui-lint holds only high-precision UI defect patterns: every rule reports its
# failing fixture and stays silent on its passing one. Fixtures are stored as
# *.fixture (tsc type-checks tests/) and copied to their real extension here;
# android ones under res/layout/, where the rule applies.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/../scripts/ui-lint"
FIX="$HERE/fixtures/ui-lint"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RULES="raw-color outline-removed click-non-interactive img-alt transition-all zoom-disabled tabindex-positive paste-blocked xaml-hardcoded-brush android-hardcoded-color android-hardcoded-text android-image-description"
for rule in $RULES; do
  check "$rule: has a failing and a passing fixture" "$(ls "$FIX" | grep -cE "^$rule\.(bad|good)\.[a-z]+\.fixture$")" "2"
done

for f in "$FIX"/*.fixture; do
  name=$(basename "$f" .fixture)          # <rule>.<bad|good>.<ext>
  rule=${name%%.*}
  rest=${name#*.}
  kind=${rest%%.*}
  case $rule in android-*) rel="res/layout/$name" ;; *) rel=$name ;; esac
  mkdir -p "$WORK/$(dirname "$rel")"
  cp "$f" "$WORK/$rel"
  out=$(cd "$WORK" && bash "$LINT" "$rel"); st=$?
  if [ "$kind" = bad ]; then
    check "$rule: the failing fixture is reported" "$(grep -c "^$rel:[0-9]*: $rule " <<<"$out")" "1"
    check "$rule: exit 1 on findings" "$st" "1"
  else
    check "$rule: the passing fixture is silent" "$out" ""
    check "$rule: exit 0 without findings" "$st" "0"
  fi
done

printf '<div>ok</div>\n' > "$WORK/plain.md"
check "a file of no UI kind is skipped" "$(cd "$WORK" && bash "$LINT" plain.md; echo "exit $?")" "exit 0"
bash "$LINT" >/dev/null 2>&1; check "usage: no file exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 3: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/ui-lint.test.sh`
Expected: FAIL lines (no `scripts/ui-lint`), exit 1.

- [ ] **Step 4: Write the implementation**

Create `plugins/dforge/scripts/ui-lint`, then `chmod +x` it:

````bash
#!/usr/bin/env bash
# High-precision UI defect patterns for the ui-ux skill, one line per finding:
#   <file>:<line>: <rule> <message>
# Each rule has a failing and a passing fixture in tests/fixtures/ui-lint/.
# Patterns read one line at a time (an Android image element across lines);
# a pattern that would need a parser does not belong here.
# Usage: ui-lint FILE...   Exit: 0 no finding, 1 findings, 2 usage.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: ui-lint FILE..." >&2; exit 2; }

PROG=$(cat <<'AWK'
function hit(rule, msg) { printf "%s:%d: %s %s\n", f, FNR, rule, msg }
kind == "web" {
  line = $0
  if (line ~ /focus-visible/) focusvis = 1
  if (!token && line !~ /^[ \t]*--[A-Za-z0-9_-]+[ \t]*:/ &&
      (line ~ /(color|background|fill|stroke|border|shadow|outline)[A-Za-z-]*["']?[ \t]*[:=][^;]*(#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*([^0-9a-zA-Z_-]|$)|rgba?\(|hsla?\()/ ||
       line ~ /-\[(#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]|rgba?\(|hsla?\()/))
    hit("raw-color", "raw colour value; use the design system token")
  if (line ~ /outline[ \t]*:[ \t]*(none|0)([ \t;!]|$)/ || line ~ /(^|[ "'`])outline-none([ "'`]|$)/) outl[FNR] = 1
  if (line ~ /<(div|span|li|td|p|img|section|article)[ \t][^>]*(onClick=|@click=|on:click=|v-on:click=)/ &&
      line !~ /role=/ && line !~ /(onKeyDown|onKeyUp|onKeyPress|@keydown|@keyup|on:keydown|on:keyup)/)
    hit("click-non-interactive", "click handler on a non-interactive element without a role and a key handler; use a button")
  if (line ~ /<img[ \t]/ && line ~ /<img[^>]*>/ && line !~ /<img[^>]*[ \t]alt=/) hit("img-alt", "image without alt text")
  if (line ~ /transition[ \t]*:[ \t]*all([ \t;]|$)/ || line ~ /(^|[ "'`])transition-all([ "'`]|$)/)
    hit("transition-all", "transition: all animates layout properties; name the properties")
  if (line ~ /user-scalable[ \t]*=[ \t]*(no|0)/ || line ~ /maximum-scale[ \t]*=[ \t]*1(\.0)?([^0-9.]|$)/)
    hit("zoom-disabled", "the viewport blocks zoom")
  if (line ~ /tab[Ii]ndex[ \t]*=[ \t]*[{"']*[ \t]*[1-9]/) hit("tabindex-positive", "a positive tabIndex breaks the natural focus order")
  if ((line ~ /onPaste=/ && line ~ /preventDefault/) || line ~ /@paste\.prevent/ || line ~ /on:paste\|preventDefault/)
    hit("paste-blocked", "blocking paste stops password managers and assistive input")
}
kind == "xaml" {
  if ($0 ~ /(Foreground|Background|Fill|Stroke|BorderBrush)="#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/)
    hit("xaml-hardcoded-brush", "hard-coded brush; use a ThemeResource or StaticResource")
}
kind == "android" {
  if ($0 ~ /android:(textColor|background|tint|backgroundTint)="#/) hit("android-hardcoded-color", "hard-coded colour; use @color/ or a theme attribute")
  if ($0 ~ /android:(text|hint|contentDescription)="[^@?"]/) hit("android-hardcoded-text", "hard-coded text; use a @string/ resource")
  if ($0 ~ /<(ImageView|ImageButton)([ \t>\/]|$)/) { inimg = 1; imgline = FNR; desc = 0 }
  if (inimg && $0 ~ /android:contentDescription=|android:importantForAccessibility="no"/) desc = 1
  if (inimg && $0 ~ />/) {
    if (!desc) printf "%s:%d: %s %s\n", f, imgline, "android-image-description", "image without contentDescription"
    inimg = 0
  }
}
END {
  if (!focusvis) for (n in outl) printf "%s:%d: %s %s\n", f, n, "outline-removed", "focus outline removed with no :focus-visible replacement"
}
AWK
)

found=0
for file in "$@"; do
  [ -f "$file" ] || continue
  case $file in
    *.tsx|*.jsx|*.vue|*.svelte|*.astro|*.html|*.css|*.scss|*.sass|*.less) kind=web ;;
    *.xaml|*.axaml) kind=xaml ;;
    *res/layout/*.xml) kind=android ;;
    *) continue ;;
  esac
  token=0
  case ${file##*/} in *token*|*theme*|*palette*|*variables*|*.config.*) token=1 ;; esac
  out=$(tr -d '\r' < "$file" | awk -v f="$file" -v kind="$kind" -v token="$token" "$PROG")
  if [ -n "$out" ]; then printf '%s\n' "$out"; found=1; fi
done
exit "$found"
````

- [ ] **Step 5: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/ui-lint.test.sh`
Expected: `N passed, 0 failed`, exit 0. A rule whose pattern misfires is fixed in the pattern, never by editing its fixture.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/ui-lint plugins/dforge/tests/ui-lint.test.sh plugins/dforge/tests/fixtures/ui-lint
git commit -m "feat(dforge): add ui-lint UI defect patterns"
```

---

### Task 5: Add the UI proof judge criteria

**Files:**
- Create: `plugins/dforge/criteria/ui-ux-proof.md`

**Interfaces:**
- Consumes: None
- Produces: `criteria/ui-ux-proof.md`, read by the judge seat in Task 7's walkthrough

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Write the criteria file**

Create `plugins/dforge/criteria/ui-ux-proof.md` with exactly this content (ASCII only):

````markdown
# UI Proof - Verifier Criteria

A judge seat reads this file, the UI/UX contract, the proof report and every
screenshot and state board the report cites, and rules whether the built UI
keeps the contract.

## Ground Truth Note

Trust only what you can see: a screenshot you opened, a state board, or a
named test whose file you read. Do NOT trust the report's verdict column, its
notes or the session's claims of success. An item whose evidence you cannot
open is unproven. A screenshot of a whole page proves nothing about a control
or a state it does not show at a readable size.

## Criteria

### Every Item Has Evidence {#coverage}

Look at the contract's items (for a touch report, its Delta items) and the
report's Results rows. Score HIGH when every item has a row whose evidence you
opened and which shows that item. Score LOW when an item has no row, its
evidence is missing or unreadable, or the evidence shows a different item or
state.

### Built Matches Promised {#fidelity}

Compare each screenshot with the state board and the UI and Output promise
items it answers. Score HIGH when components, tokens, hierarchy, spacing
rhythm and copy match what was promised; pixel offsets need not. Score LOW
when the build drops an element, substitutes a different component, uses
colours or type outside the design system, or changes the copy.

### Every State Is Shown {#states}

Look at the contract's state matrix and interaction items. Score HIGH when
each data state (loading, empty, error, worst-case content and the others the
contract lists) and each control state (hover, keyboard focus, disabled,
pending, invalid) has a screenshot or a test at the viewports and themes the
report names, and the keyboard-only walk is evidenced. Score LOW when only the
default path is shown.

### Deviations Are Cited {#deviations}

Look at every row marked deviation and every difference you found yourself.
Score HIGH when each one cites the user's answer, a profile decision or an
accessibility need that forced it. Score LOW when a difference is uncited or
marked pass.

## Output

Score each criterion 1 to 20. List each disputed item as
"- <ID>: <what the evidence shows instead>". The verdict is ship only when
every criterion scores 15 or more and no item is disputed; otherwise it is
fix. End with exactly one line, "Verdict: ship <fingerprint>" or
"Verdict: fix <fingerprint>", using the fingerprint the dispatch names.
````

- [ ] **Step 2: Run the criteria suite**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/criteria.test.sh`
Expected: the `ui-ux-proof:` lines all `ok` (ground truth note, criteria section, 2 to 4 criteria, pinned unique ids, ASCII), `0 failed`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add plugins/dforge/criteria/ui-ux-proof.md
git commit -m "feat(dforge): add the UI proof judge criteria"
```

---

### Task 6: Write the contract, state and interaction references

**Files:**
- Create: `plugins/dforge/skills/ui-ux/references/contract-template.md`
- Create: `plugins/dforge/skills/ui-ux/references/state-catalogue.md`
- Create: `plugins/dforge/skills/ui-ux/references/interaction-rules.md`

**Interfaces:**
- Consumes: None
- Produces: the three references Task 8's SKILL.md links

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

None of these files may contain the string `dforge:ui-ux` (the skill directory gains its SKILL.md only in Task 8; `validate-repository.mjs` resolves names). They link nothing outside `references/`.

- [ ] **Step 1: Write `contract-template.md`**

Create `plugins/dforge/skills/ui-ux/references/contract-template.md` with exactly:

`````markdown
# UI/UX contract template

## The section

The contract is one spec section, `## UI/UX contract`. Its first line is the
depth line; the three parts follow as `###` headings. Every item is either a
bullet that starts with its bold ID, continued on lines indented by two
spaces, or a table row whose first cell is the ID. IDs are numbered per part,
never repeat and are never reused. `scripts/ui-proof contract <spec>` lists
the IDs the parser sees; run it after writing the section.

````markdown
## UI/UX contract

**UI/UX depth:** feature — a new settings screen and its save flow

### UI

- **UI-1** — Settings page: `SidebarLayout` with one `Card` per group, tokens
  `surface` and `muted-foreground`, no raw values.
  Board: `docs/ux/boards/settings.png` (default, saving, saved, error).
- **UI-2** — Typography: page title `heading-lg`, group titles `heading-sm`,
  help text `body-sm muted`.

### UX

- **UX-1** — Flow "change display name": entry from the account menu and the
  deep link `/settings#profile`; Save is disabled until the value changes;
  Escape or Cancel restores the saved value; back returns to the previous page.
- **UX-2** — State matrix, profile card:

  | State | Shows |
  |---|---|
  | loading | skeleton of the card, no layout shift |
  | error | "Couldn't load your profile" and a Retry button |
  | worst case | a 64-character name wraps inside the card |

- **UX-3** — Saving: the button shows its pending state after 200 ms, the
  toast says "Saved", focus stays on the field.

### Output promise

| ID | Promise |
|---|---|
| OP-1 | The built screens match boards UI-1 in components, tokens, hierarchy and copy; pixel offsets may differ. |
| OP-2 | Proven at 375x812, 768x1024 and 1440x900, light and dark themes. |
| OP-3 | WCAG 2.2 AA; LCP under 2.5 s on the settings route. |
| OP-4 | Declared deviation: no avatar upload (out of scope, owner 2026-10-24). |
````

## What each part holds

**UI (`UI-<n>`) — the interface.** The component map: every mockup region
mapped to an existing component of the design system and its tokens, never a
raw value; layout and hierarchy; typography; imagery and iconography; the
theme variants; the state boards, each with its path and the states it shows.

**UX (`UX-<n>`) — the experience.** Users and their jobs; every flow with its
entry points, alternate paths, cancel, undo, back and deep links; a state
matrix per surface (walk `state-catalogue.md`); interactions and feedback,
including where focus goes after each action (walk `interaction-rules.md`);
forms and validation; the copy deck; responsive changes per breakpoint; motion
and its reduced-motion fallback; accessibility; non-functional requirements
with numbers (performance budgets, data volumes, i18n and right-to-left,
supported platforms).

**Output promise (`OP-<n>`) — what the shipped result guarantees as a whole.**
Which state boards are binding and how closely; the viewports, themes and
platforms it is proven on; the accessibility level; the budgets; every
declared deviation from the mockup with its reason; what is out of scope.
`OP-` items are proven, not built: no plan task has to name them, every proof
must cover them.

## From items to acceptance

Each item becomes one or more acceptance statements whose text starts with
its ID:

```
A12. [test, high] UX-1: Escape restores the saved display name and keeps focus on the field.
A13. [demo, high] UI-1: The settings page matches its board in light and dark themes.
```

Tag a behaviour statement `test` when the profile's `**UI test runner:**`
names a runner the project can run; otherwise tag it `demo`. Either way, its
row in the proof report proves it.

## The touch delta

At touch depth there is no spec section. The proof report starts with a
`## Delta` section in the same item format: the depth line, then 5 to 15
items naming the states, viewports, themes and neighbouring surfaces the
change affects.

````markdown
## Delta

**UI/UX depth:** touch — the date picker closes on Escape

- **UX-1** — Escape closes the picker and returns focus to the date field.
- **UX-2** — The picker still opens by keyboard (Enter, Space) and pointer.
- **UI-1** — Dark theme: the focus ring stays visible on the field.
- **OP-1** — Proven at 375x812 and 1440x900, light and dark.
````

## Profile

`<docs>/ui-ux/profile.md`, created the first time the skill runs in a project
and read before every UI task. Ask the user for what the repository cannot
tell you. `**UI paths:**` takes bash case patterns matched against
repository-relative paths (`*` crosses `/`); without it the platform defaults
apply (`scripts/ui-proof paths` prints them).

````markdown
# UI profile

**Platform:** web
**Harness:** `npm run dev`, served at http://localhost:5173, driven by Playwright MCP
**UI test runner:** `npx playwright test`
**UI paths:** `src/*.tsx` `src/*.css`
**Design system:** darkraise-ui 7.x, theme in `src/theme.config.ts`
**Token paths:** `src/theme.config.ts`
**Viewports:** 375x812, 768x1024, 1440x900
**Themes:** light, dark
**Users:** photographers culling a shoot on a laptop, keyboard-heavy
**Voice:** plain, sentence case, verbs on buttons
**Screenshots:** local

## Decisions

- 2026-10-24 — Toasts confirm saves; dialogs only for destructive actions.
````
`````

- [ ] **Step 2: Write `state-catalogue.md`**

Create `plugins/dforge/skills/ui-ux/references/state-catalogue.md` with exactly:

````markdown
# State catalogue

Walk this catalogue for every surface and control in the contract. Each state
the surface can reach goes into its state matrix item; a state it cannot reach
is named as unreachable, so the judge does not count it missing.

## Data states (per surface)

| State | Define |
|---|---|
| loading, first load | what shows, whether layout shifts, when a skeleton appears |
| loading, refresh | whether the old data stays visible |
| empty, first use | what belongs here and the one next action |
| empty, filtered | which filter emptied it and how to clear it |
| partial | some items failed or are still loading |
| error | what happened, how to recover, what stays usable |
| offline | what still works and what is queued |
| permission denied | what the user may do instead |
| stale or conflicting | someone else changed it meanwhile |
| worst-case content | see Worst-case data |
| success | how completion is confirmed |

## Control states (per interactive element)

Default, hover, keyboard focus, active (pressed), disabled (and why), pending,
selected or checked, invalid, read-only.

## Flow states

- Every entry point, deep links included.
- The main path, step by step.
- Alternate paths, and cancel at every step.
- Undo and back.
- Session expiry or reauthentication mid-flow.
- Interruption (closing the window, losing the connection) and how it resumes.

## Worst-case data

Demo data is chosen to make a design look good. The proof uses data chosen to
break it:

- the longest realistic names, titles and labels, and one unbroken string
  (a URL or an identifier);
- the largest realistic counts: items, columns, notifications, digits in
  amounts;
- empty, null and missing values for every optional field, and a missing
  image;
- right-to-left text, diacritics and emoji;
- zero, one and many of every collection;
- dates at the boundaries: today, the far past, the far future, other time
  zones.

Load it through the same boundary the real data uses (the API, a fixture, a
seed script), never by editing the component. A development-only switch
between demo and worst-case data is the cheapest way to keep it.
````

- [ ] **Step 3: Write `interaction-rules.md`**

Create `plugins/dforge/skills/ui-ux/references/interaction-rules.md` with exactly:

````markdown
# Interaction rules

Checkable defaults for every control and flow in a UI/UX contract. The
contract may override a rule with its reason; the proof report then cites that
reason on the deviation row. Sources: the Vercel Web Interface Guidelines,
WCAG 2.2 AA, Nielsen's usability heuristics, and the copy guidance of
Anthropic's frontend-design skill.

## Feedback and latency

- Every action responds within 100 ms: a pressed state, a pending state or
  the result.
- A pending indicator waits 150-300 ms before it shows and stays at least
  300-500 ms once shown, so fast responses do not flicker.
- A button that starts work stays enabled until the request starts, then
  shows its pending state and cannot submit twice.
- An optimistic update that the server refuses rolls back visibly, with the
  reason.
- Success is confirmed where the user is looking; a confirmation names the
  action in the past tense ("Published" for "Publish").

## Forms

- Every input has a visible label; a placeholder is never the label.
- Validation runs on blur or on submit, not on every keystroke before the
  first blur.
- On submit, focus moves to the first invalid field.
- An error sits next to its field, is tied to it for assistive technology,
  and says what is wrong and how to fix it.
- Input survives an error, a failed request and a back navigation.
- Paste is never blocked; input types and autocomplete match the data.
- Leaving with unsaved changes asks first.

## Focus and keyboard

- Every action is reachable and operable by keyboard alone, in visual order.
- Focus is always visible.
- A dialog moves focus inside when it opens, keeps it there while open,
  closes on Escape and returns focus to its trigger.
- After a deletion, focus moves to the next sensible element, never to the
  top of the page.

## Navigation and state

- Filters, tabs, pagination, sort and open panels live in the URL or the
  platform's restorable state, so reload, back and share keep them.
- Back returns to the previous view with its scroll position and state.
- Links navigate; buttons act.

## Destructive actions

- A destructive action names what it destroys ("Delete 3 files?") and its
  buttons name the outcomes ("Delete files", "Keep files").
- Prefer undo to a confirmation for reversible actions.

## Copy

- Name things by what the user understands, not by how the system is built.
- An action keeps one name through the whole flow.
- Errors say what happened and how to fix it, without apology or vagueness.
- An empty state says what belongs there and offers one next action.
- Sentence case, no filler; numbers, dates and currencies formatted for the
  locale.

## Responsive and touch

- Each breakpoint states what changes (navigation collapses, a table becomes
  a list), not only what shrinks.
- Touch targets are at least 44 x 44 px; never below WCAG 2.2's 24 x 24 px.
- No horizontal scroll at the narrowest viewport outside content meant to
  scroll.
- Every hover-only affordance has a touch and a keyboard equivalent.
- Content respects safe areas on devices with notches.

## Motion

- Motion explains a change (opening, moving, confirming); decoration is rare.
- Animate transform and opacity, not layout properties; never
  `transition: all`.
- Feedback motion lasts 150-300 ms and can be interrupted.
- The reduced-motion setting replaces movement with a fade or with nothing.

## Accessibility

- Text contrast at least 4.5:1, large text and UI components at least 3:1,
  in every theme.
- State is never conveyed by colour alone.
- Every control has an accessible name; icon-only buttons have a label.
- Status changes (saved, failed, results loaded) are announced to assistive
  technology.
- Zoom to 200% keeps the content usable; the viewport never disables zoom.

## Performance

- The contract states numeric budgets; on the web the defaults are LCP under
  2.5 s, INP under 200 ms and CLS under 0.1.
- Lists longer than the contract's threshold are virtualized or paginated.
- Images reserve their dimensions, so loading does not shift layout.

## Internationalization and theming

- No text in images; strings come from the project's string resources when
  it has them.
- Layouts survive strings 30% longer and right-to-left text.
- Every theme the profile names is proven, high contrast included where the
  platform has it.
````

- [ ] **Step 4: Check and commit**

```bash
grep -c 'dforge:ui-ux' plugins/dforge/skills/ui-ux/references/*.md   # expect 0 for each file
timeout 60 node scripts/validate-repository.mjs                         # expect exit 0
git add plugins/dforge/skills/ui-ux/references
git commit -m "docs(dforge): add the ui-ux contract references"
```

---

### Task 7: Write the walkthrough and platform guides

**Files:**
- Create: `plugins/dforge/skills/ui-ux/references/walkthrough.md`
- Create: `plugins/dforge/skills/ui-ux/references/platforms/{web,windows,linux-desktop,android,terminal}.md` (one shape)

**Interfaces:**
- Consumes: the Task 1 note; `scripts/ui-proof` (Contracts); `criteria/ui-ux-proof.md` (Task 5)
- Produces: the references Task 8's SKILL.md links

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

No file may contain the string `dforge:ui-ux` (Task 8 creates the skill). Read the Task 1 note first: when it records that the absolute worktree path was written, keep Step 6's text as given; when it records a refusal, swap the order of the two sentences in Step 6 so the bare-filename-then-move route comes first, and keep both.

- [ ] **Step 1: Write `walkthrough.md`**

Create `plugins/dforge/skills/ui-ux/references/walkthrough.md` with exactly:

`````markdown
# The walkthrough

The Prove phase. Run it in the session or in an implementer seat: judge seats
have no browser or device tools. Every step writes evidence the proof report
cites. A step you cannot run becomes an `unverifiable` row with its reason,
never a silent skip.

## Before you start

- Read the contract (the spec's `## UI/UX contract`, or at touch depth the
  `## Delta` you are about to write) and the profile
  (`<docs>/ui-ux/profile.md`).
- Open the guide for the profile's `**Platform:**` under `platforms/`:
  [web](platforms/web.md), [windows](platforms/windows.md),
  [linux-desktop](platforms/linux-desktop.md),
  [android](platforms/android.md), [terminal](platforms/terminal.md).
  macOS and iOS have no guide: their items are `unverifiable`.
- Pick the slug: the spec's file name without its date and `-design.md`, or at
  touch depth the bug in a few words. Evidence goes to
  `<checkout>/.dforge/ui-ux/<slug>/`. Create it; `.dforge/` is ignored by git
  through its own `.gitignore` holding `*` (write that file when it is
  missing).

## Steps

1. **Launch** the UI through the guide's launch step. Start every server,
   emulator or session as a tracked background task, note its PID, and give
   every command a timeout.
2. **Seed the worst-case data** through the boundary the real data uses
   (`state-catalogue.md` §Worst-case data).
3. **Walk every flow** in scope, first by pointer, then by keyboard alone, at
   every viewport and theme the profile and the Output promise name.
4. **Force every state** in the matrix: the guide says how (on the web, route
   the network to slow, failing, empty and huge responses).
5. **Run the automated checks** the guide lists: accessibility scan, console
   or log errors, overflow, contrast. Record each result for the report's
   `## Automated checks`.
6. **Screenshot each item and state**, named
   `<id>-<viewport>-<theme>[-<state>].png`, beside the state board it answers.
   Pass the tool the absolute path
   `<checkout>/.dforge/ui-ux/<slug>/<name>.png`. When the tool refuses that
   path, save with the bare file name and move the file from where the tool
   reports it into `.dforge/ui-ux/<slug>/`.
7. **Write the report** (format below) at
   `<docs>/ui-ux/proofs/<YYYY-MM-DD>-<slug>.md`.
8. **Stamp it:** `bash <plugin-root>/scripts/ui-proof stamp <report>`.
9. **Have it judged** (below), save the reply, and add the Judge line.
10. **Check:** `bash <plugin-root>/scripts/ui-proof check --base <ref>`, adding
    `--spec <spec>` when the work has a contract. `<ref>` is the commit the
    work started from. Fix the UI or the proof until it exits 0.
11. **Clean up:** close the browser or app, stop every process you started
    (`pkill -P <pid>` then `kill <pid>`, repeated for grandchildren), and
    remove the `.playwright-mcp/` files you created. Confirm with `ps` that
    nothing you started is left.
12. **Commit** the report and its `.judge.md`, and on a first run
    `<docs>/ui-ux/profile.md`: they are not UI files, so committing them
    leaves the stamp current, and the report is the record that survives the
    worktree.

Any UI edit after step 8 makes the stamp stale: stamp again, and since the
stamp drops a judge line for another fingerprint, judge again.

## The report

````markdown
# UI proof: Settings screen

**Contract:** docs/dforge/specs/2026-10-24-settings-design.md
**Platform:** web
**Viewports:** 375x812, 768x1024, 1440x900
**Themes:** light, dark
**Evidence:** local
**Fingerprint:** 3f9a0c1e5b7d2a46
**Judge:** ship 3f9a0c1e5b7d2a46 — docs/dforge/ui-ux/proofs/2026-10-24-settings.judge.md

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/settings/ui-1-1440x900-light.png, .dforge/ui-ux/settings/ui-1-375x812-dark.png | |
| UX-2 | deviation | .dforge/ui-ux/settings/ux-2-1440x900-light-error.png | cites: user answer 2026-10-24, no Retry on the error card |
| UX-3 | pass | A14: saving shows the pending state | |
| OP-2 | unverifiable | - | no tablet emulator on this host |

**Accepted by:** "fine without the tablet run for now"

## Automated checks

- axe: 0 serious, 0 critical
- console errors: 0
- horizontal overflow at 375: none
````

- `**Contract:**` is the spec's path, or `touch` with a `## Delta` section
  above `## Results` (`contract-template.md` §The touch delta).
- One row per contract ID (per Delta ID at touch depth), `OP-` IDs included.
- `pass` and `deviation` rows cite at least one screenshot or test name.
- A `deviation` note starts `cites:` and names the user's answer, the profile
  decision or the accessibility need that forced it. An uncited difference is
  a `fail`.
- `unverifiable` passes the gate only with an `**Accepted by:**` line quoting
  the user. Never write that line unless the user said, in this
  conversation, that they accept the item unproven.
- `**Evidence:** local` while screenshots live under `.dforge/`; they go when
  the worktree is removed, and the verdict rows are what remains. With the
  profile's `**Screenshots:** commit`, put them beside the report and write
  `committed`.

## The judge

Dispatch `dforge:judge-opus` at feature and product depth and
`dforge:judge-sonnet-high` at touch depth (on a Codex host, the native judge
`reference/native-codex.md` names for that rank):

```
Subagent (judge seat):
  description: "Judge the UI proof"
  prompt: |
    You judge whether a built UI keeps its UI/UX contract. Assume every item
    is unproven until a screenshot you opened or a test you read shows it.

    **Criteria:** [PLUGIN_ROOT]/criteria/ui-ux-proof.md
    **Contract:** [SPEC_PATH and its "## UI/UX contract", or the report's "## Delta"]
    **Report:** [REPORT_PATH]
    **Evidence:** every file the report cites, under [EVIDENCE_DIR], and the state boards the contract names
    **Fingerprint:** [FINGERPRINT]

    Read the criteria, the contract and the report. Open every cited
    screenshot and board. Then answer as the criteria's Output section says,
    ending with exactly one line: "Verdict: ship [FINGERPRINT]" or
    "Verdict: fix [FINGERPRINT]".
```

Save the reply verbatim beside the report as `<report name>.judge.md`, then
add `**Judge:** <ship|fix> <fingerprint> — <that file's repository path>` to
the report's header. On `fix`, correct what the judge disputes, then rerun
from step 8. A judge reply that does not end with the verdict line is
re-dispatched once with that instruction repeated.
`````

- [ ] **Step 2: Write the platform guides**

Create each file under `plugins/dforge/skills/ui-ux/references/platforms/` with the content below.

`web.md`:

````markdown
# Web

**Status:** verified 2026-10-24 on Linux with Playwright MCP (the probe in the spec's riskiest assumption).

- **Launch:** the profile's Harness command (a dev server) as a background
  task; wait for its URL to answer (`curl -s -o /dev/null -w '%{http_code}'`).
  Electron apps run through the project's Playwright runner with Playwright's
  Electron support.
- **Drive:** Playwright MCP. Load the `mcp__playwright__*` tools with
  ToolSearch: `browser_navigate`, `browser_resize` (each viewport),
  `browser_click`, `browser_type`, `browser_press_key` (`Tab`, `Shift+Tab`,
  `Enter`, `Escape`, arrows for the keyboard walk), `browser_snapshot` (the
  accessibility tree: names, roles and the `[active]` focus marker),
  `browser_take_screenshot`, `browser_close`.
- **Themes:** `browser_run_code_unsafe` with
  `await page.emulateMedia({ colorScheme: 'dark' })`, or the app's own theme
  switch; reduced motion with `emulateMedia({ reducedMotion: 'reduce' })`.
- **Force states:** `browser_run_code_unsafe` with `page.route` to delay,
  fail (`route.fulfill({ status: 500 })`), empty or enlarge responses, then
  reload.
- **Automated checks:** `browser_console_messages` for errors; overflow with
  `browser_evaluate` of
  `document.documentElement.scrollWidth > document.documentElement.clientWidth`;
  an axe scan when the project has `axe-core` installed (`page.addScriptTag`
  with its `axe.min.js`, then `axe.run()`), otherwise record the scan as not
  run in `## Automated checks`.
- **UI test runner:** when the profile names one (for example
  `npx playwright test`), `test`-tagged statements run there, and their test
  names are evidence.
````

`windows.md`:

````markdown
# Windows desktop

**Status:** unverified — no session has run this guide yet. The first run on a Windows host replaces this line with the date and what ran.

- **Launch:** the profile's Harness command, or the built executable, as a
  background process; note its PID and kill its tree with
  `taskkill /F /T /PID <pid>` when done.
- **Drive:** the project's own harness when it has one (for example a
  GuiVerify-style check runner); otherwise UI Automation through FlaUI (C#) or
  pywinauto (Python): find elements by AutomationId, invoke, type, and send
  `{TAB}`, `{ENTER}` and `{ESC}` for the keyboard walk.
- **Screenshots:** the harness's capture, FlaUI `Capture.Element`, or
  pywinauto `capture_as_image()`, saved by absolute path into the evidence
  directory.
- **Themes and scale:** light and dark app mode, a high-contrast theme, and
  display scale 100% and 150%.
- **Accessibility:** the UI Automation tree gives each control's Name,
  ControlType and keyboard focus; an unnamed focusable control is a finding.
- Runs only on a Windows host; elsewhere the items are `unverifiable`.
````

`linux-desktop.md`:

````markdown
# Linux desktop

**Status:** unverified — no session has run this guide yet. The first run replaces this line with the date and what ran.

- **Launch:** `Xvfb :99 -screen 0 1440x900x24 &` (note its PID), then the app
  with `DISPLAY=:99` as a background task. GTK, Qt and Tauri apps all run
  this way.
- **Drive:** `xdotool` (`search --name`, `windowactivate`, `key Tab`,
  `key Return`, `key Escape`, `type`, `mousemove` and `click`).
- **Screenshots:** `import -display :99 -window root <file>` (ImageMagick) or
  `xwd -root -display :99 | convert xwd:- <file>`.
- **Themes:** `GTK_THEME=Adwaita:dark` for GTK, `QT_QPA_PLATFORMTHEME` or the
  app's own setting for Qt.
- **Accessibility:** the AT-SPI tree (`python3` with `pyatspi`, or
  Accerciser) for names, roles and focus.
- **Clean up:** kill the app, then Xvfb.
````

`android.md`:

````markdown
# Android

**Status:** unverified — no session has run this guide yet. The first run replaces this line with the date and what ran.

- **Launch:** `emulator -avd <name> -no-window -no-audio &` (note its PID),
  `adb wait-for-device`, then `adb install -r <apk>` and
  `adb shell am start -n <package>/<activity>`.
- **Drive:** `adb shell input tap <x> <y>`, `input text <text>`,
  `input keyevent 61` (Tab), `66` (Enter), `111` (Escape).
- **Screenshots:** `adb exec-out screencap -p > <file>`.
- **Themes and text size:** `adb shell cmd uimode night yes|no`;
  `adb shell settings put system font_scale 1.3` for large text.
- **Accessibility:** `adb shell uiautomator dump` and read the XML for
  `content-desc`, `focusable` and `focused`.
- **Clean up:** `adb emu kill`, then confirm the emulator PID is gone.
````

`terminal.md`:

````markdown
# Terminal UI

**Status:** unverified — Task 18 of the ui-ux plan runs this guide; the run replaces this line with the date and what ran.

- **Launch:** `tmux new-session -d -s uiux -x 80 -y 24 '<command>'`. The
  profile's UI paths must name the TUI's source files: there are no defaults
  for terminals.
- **Drive:** `tmux send-keys -t uiux <keys>` (`Tab`, `Enter`, `Escape`,
  `Up`, `Down`, literal text with `-l`).
- **Capture:** `tmux capture-pane -t uiux -p -e > <file>.ansi` at 80 columns,
  then `tmux resize-window -t uiux -x 120 -y 40` and capture again. A
  captured pane is the evidence for a terminal row (cite the `.ansi` file).
- **Themes:** run once with `NO_COLOR=1` and once with colour; check that no
  state is shown by colour alone.
- **Clean up:** `tmux kill-session -t uiux`.
````

Note: the ui-proof check counts only image extensions (`.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`) as files that must exist; an `.ansi` capture is cited like a test name. That is intended for terminal rows.

- [ ] **Step 3: Check and commit**

```bash
grep -rc 'dforge:ui-ux' plugins/dforge/skills/ui-ux/references   # expect 0 everywhere
timeout 60 node scripts/validate-repository.mjs                   # expect exit 0 (links resolve)
git add plugins/dforge/skills/ui-ux/references
git commit -m "docs(dforge): add the ui-ux walkthrough and guides"
```

---

### Task 8: Write the ui-ux skill

**Files:**
- Create: `plugins/dforge/skills/ui-ux/SKILL.md`
- Test: `plugins/dforge/tests/ui-ux-skill.test.sh`

**Interfaces:**
- Consumes: the references from Tasks 6-7; `scripts/ui-proof` and `scripts/ui-lint` (Contracts)
- Produces: the `dforge:ui-ux` skill; `tests/ui-ux-skill.test.sh`, which Tasks 14-16 extend

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/ui-ux-skill.test.sh`:

````bash
#!/usr/bin/env bash
# The ui-ux skill and the instructions that route to it and gate on it: each
# check is a whole instruction, not a keyword, so a rewording that drops the
# rule fails here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/skills/ui-ux/SKILL.md"
R="$P/skills/ui-ux/references"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

# --- the skill ---
check "the skill exists" "$([ -f "$S" ] && echo yes || echo no)" "yes"
check "its name is ui-ux" "$(sed -n '2p' "$S")" "name: ui-ux"
names "the description triggers on anything a user sees or does" "$S" 'description: Use when work touches anything a user sees or does'
names "the description triggers on UI bug fixes" "$S" 'fixing a bug whose fix changes the UI'
names "the depth line" "$S" '`**UI/UX depth:** <touch|feature|product> — <why>`'
names "state boards are asked at every depth" "$S" 'Ask at every depth; recommend yes at'
names "demo when no UI test runner" "$S" 'is tagged `demo` when the profile names no UI test runner'
names "the gate command" "$S" 'scripts/ui-proof check --base <ref> [--spec <spec>]'
names "the pending line" "$S" '`UI proof: pending — <why>`'
names "Accepted by needs the user's words" "$S" 'Never write `**Accepted by:**` unless the user said'
names "Codex runs the scripts by hand" "$S" 'runs no hooks: run `bash <plugin-root>/scripts/ui-lint'
for f in contract-template.md state-catalogue.md interaction-rules.md walkthrough.md \
         platforms/web.md platforms/windows.md platforms/linux-desktop.md platforms/android.md platforms/terminal.md; do
  check "reference $f exists" "$([ -f "$R/$f" ] && echo yes || echo no)" "yes"
done
for f in windows linux-desktop android; do
  names "$f guide ships marked unverified" "$R/platforms/$f.md" '**Status:** unverified'
done
check "no macOS or iOS guide" "$(ls "$R/platforms" | grep -ciE 'mac|ios')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: FAIL for the skill lines (no SKILL.md), the reference lines `ok`, exit 1.

- [ ] **Step 3: Write the skill**

Create `plugins/dforge/skills/ui-ux/SKILL.md` with exactly:

`````markdown
---
name: ui-ux
description: Use when work touches anything a user sees or does - designing, building or changing screens, components, flows, forms, copy, styling, layout, interaction, accessibility or responsive behaviour, turning a mockup or design into code, or fixing a bug whose fix changes the UI - writes a UI/UX contract, carries it into every UI task, and proves it in the running UI before the work counts as done.
---

# UI/UX

## Overview

A mockup shows one state of one path. What is not drawn is not built: the
states, the flows, the feedback, the copy, the responsive changes, the
accessibility and the budgets fall away, and the build copies the layout.
This skill turns the design into a numbered contract, carries every item to
the task that builds it, and proves each one in the running UI.

**Core principle:** UI work is done when `ui-proof check` passes, not when it
looks right in one screenshot.

This skill owns the process. Aesthetic direction comes from the
frontend-design skill when it is installed, components and tokens from the
project's design system (for example darkraise-ui); call on them, and do not
restate them here.

## The Iron Law

```
NO UI WORK IS DONE WITHOUT A PASSING ui-proof check
```

The final review, finishing and every "done" claim run it. On Claude Code a
Stop hook holds a turn that leaves UI changes unproven.

## Depth

State one line before anything else:

`**UI/UX depth:** <touch|feature|product> — <why>`

| Depth | When | What it takes |
|---|---|---|
| touch | a bug fix, a copy or styling change, one surface | a `## Delta` of 5 to 15 items in the proof report, a proof of that surface, the judge-sonnet-high seat |
| feature | a new or changed flow or screen | a `## UI/UX contract` section in the spec, a walkthrough of every flow it touches, the judge-opus seat |
| product | a new product or surface family | the feature depth plus the profile's design decisions, written or extended |

## The project UI profile

Read `<docs>/ui-ux/profile.md` before any UI task
(`bash <plugin-root>/scripts/dforge-path docs ui-ux/profile.md` prints its
path). When it does not exist, create it from
[contract-template.md](references/contract-template.md) §Profile, asking the
user for what the repository cannot tell you: who uses the product, the
platform and how to launch it, the viewports and themes. Its existence turns
the gate on for the project.

## Shape

Run before acceptance statements are drafted (from dforge:brainstorming) and
before the fix (from dforge:systematic-debugging, at touch depth).

1. Read the profile, or create it.
2. Write the contract (feature, product) or the delta (touch) from
   [contract-template.md](references/contract-template.md), walking
   [state-catalogue.md](references/state-catalogue.md) for every surface and
   [interaction-rules.md](references/interaction-rules.md) for every control.
3. Ask the user whether to build state boards: every state of each screen
   side by side, annotated with contract IDs, built from the project's real
   components where the platform allows. Ask at every depth; recommend yes at
   feature and product depth and no at touch depth.
4. Define the worst-case dataset the proof will use
   ([state-catalogue.md](references/state-catalogue.md) §Worst-case data).

Under `autoRun=on`, brainstorming asks nothing after its clarifying
questions: ask the profile and state-board questions among them, and quote
the answers in the spec's `## Decisions`.

Every contract item becomes one or more acceptance statements whose text
starts with its ID, for example `A12. [test, high] UX-4: Escape closes the
dialog and returns focus to its trigger.` A behaviour statement is tagged
`test` when the profile names a UI test runner the project can run, and
is tagged `demo` when the profile names no UI test runner. Either way, its
proof-report row proves it.

## Carry

- **The plan.** Every task whose files match `ui-proof paths` carries a
  `**UI/UX:**` line naming the contract IDs it delivers, and every `UI-` and
  `UX-` ID reaches some task. `scripts/plan-lint` enforces both.
- **The brief.** `scripts/task-brief` appends the cited items verbatim under
  `## UI/UX contract items`.
- **The implementer** renders its work through the profile's harness before
  reporting, and maps each cited ID to a screenshot path or a test name.

## Prove

Follow [walkthrough.md](references/walkthrough.md): launch through the
platform guide, seed the worst-case data, walk every flow by pointer and by
keyboard at every viewport and theme, force every state, run the automated
checks, screenshot each item, write the proof report, stamp it with
`ui-proof stamp`, and have the judge seat review it. Run the walkthrough in
the session or an implementer seat: judge seats have no browser.

## The gate

```bash
bash <plugin-root>/scripts/ui-proof check --base <ref> [--spec <spec>]
```

That is `scripts/ui-proof check --base <ref> [--spec <spec>]`, where `<ref>`
is the commit the work started from: the final review and finishing pass
`MERGE_BASE` and the plan's spec, a "done" claim passes the branch's base.
Exit 1 names each failed step; fix the UI or the proof, never the check.

An `unverifiable` row (no harness for the platform on this host; macOS and
iOS are not supported) passes only with an `**Accepted by:**` line quoting the
user. Never write `**Accepted by:**` unless the user said, in this
conversation, that they accept the item unproven, and quote their words.

When the proof cannot happen in this turn, end the message with the line
`UI proof: pending — <why>`. It releases the Stop hook's hold and tells the
user the UI is unproven; it never satisfies the gate.

## Hooks and Codex

On Claude Code, after each edit to a UI file a hook returns `scripts/ui-lint`
findings and, once per session, names this skill; at each stop a hook holds a
turn whose UI changes have no passing proof, once (its retry passes). Codex
runs no hooks: run `bash <plugin-root>/scripts/ui-lint <files>` after UI
edits and `ui-proof check` before claiming done. Whether a Codex native
implementer can drive a browser is unverified.

## Red Flags

| Thought | Reality |
|---|---|
| "It matches the mockup" | The mockup is one state. Prove every state in the matrix. |
| "The states are obvious; I'll add them while building" | What is not in the contract is not built. Write the item first. |
| "One full-page screenshot shows it works" | A thumbnail hides the failures that matter. Screenshot each item and state. |
| "The demo data looks fine" | Demo data is chosen to look good. Prove with the worst-case data. |
| "Keyboard users are an edge case" | Walk every flow by keyboard alone. |
| "The judge will catch it" | The judge reads your evidence. Missing evidence is a fail. |
| "I'll mark it unverifiable" | Only the user can accept an unverifiable item. |
| "It's only a styling fix" | Touch depth still has a delta and a proof. |

## Quick Reference

| Command | Does |
|---|---|
| `ui-proof paths` | the globs that count as UI files |
| `ui-proof fingerprint` | the current UI fingerprint |
| `ui-proof contract <spec> [ID...]` | the contract's IDs, or the items verbatim |
| `ui-proof stamp <report>` | write the fingerprint; drop a stale judge line |
| `ui-proof check --base <ref> [--spec <spec>]` | the gate |
| `ui-lint <file>...` | high-precision UI defect patterns |
`````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: `N passed, 0 failed`, exit 0. Then `timeout 60 node scripts/validate-repository.mjs` exits 0 and `timeout 120 /root/.local/bin/claude plugin validate plugins/dforge` passes (acceptance A1).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/ui-ux/SKILL.md plugins/dforge/tests/ui-ux-skill.test.sh
git commit -m "feat(dforge): add the ui-ux skill"
```

---

### Task 9: Add the PostToolUse lint and reminder hook

**Files:**
- Create: `plugins/dforge/scripts/ui-edit-hook.sh`
- Modify: `plugins/dforge/hooks/hooks.json`
- Test: `plugins/dforge/tests/ui-hooks.test.sh`

**Interfaces:**
- Consumes: `scripts/lib/ui-ux.sh`, `scripts/ui-lint` (Contracts)
- Produces: the PostToolUse hook (Contracts); `tests/ui-hooks.test.sh`, which Task 10 extends

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/ui-hooks.test.sh`:

````bash
#!/usr/bin/env bash
# The ui-ux hooks: after an edit to a UI file, PostToolUse returns ui-lint's
# findings and names dforge:ui-ux once per session; at a stop, a turn that
# leaves UI changes without a passing proof is held once.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDIT="$HERE/../scripts/ui-edit-hook.sh"
HOOKS="$HERE/../hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.email t@example.com && git config user.name t
mkdir -p src
printf 'export const App = () => <main>Hi</main>;\n' > src/App.tsx
printf '# readme\n' > README.md
git add . && git commit -q -m base

edit() { # edit <session> <file> [transcript]
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg f "$2" --arg tp "${3:-}" \
    '{hook_event_name:"PostToolUse",session_id:$sid,cwd:$cwd,transcript_path:$tp,tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$EDIT"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1" 2>/dev/null; }

# --- PostToolUse ---
check "edit: a non-UI file prints nothing" "$(edit e-1 "$REPO/README.md")" ""
out=$(edit e-1 "$REPO/src/App.tsx")
check "edit: the first UI edit names the skill" "$(ctx "$out" | grep -c 'Load dforge:ui-ux')" "1"
check "edit: the event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" "PostToolUse"
check "edit: never a decision" "$(jq -r '.decision // "none"' <<<"$out")" "none"
check "edit: a clean UI file after the reminder prints nothing" "$(edit e-1 "$REPO/src/App.tsx")" ""
printf '<img src="a.png">\n' > src/Bad.tsx
out=$(edit e-1 "$REPO/src/Bad.tsx")
check "edit: lint findings name the rule and line" "$(ctx "$out" | grep -c 'src/Bad.tsx:1: img-alt')" "1"
check "edit: no second reminder" "$(ctx "$out" | grep -c 'Load dforge:ui-ux')" "0"
TR="$TMP/skill.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:"dforge:ui-ux"}}]}}' > "$TR"
check "edit: a session that loaded the skill gets no reminder" "$(edit e-2 "$REPO/src/App.tsx" "$TR")" ""
check "edit: a relative path resolves against cwd" "$(ctx "$(edit e-3 src/Bad.tsx)" | grep -c 'img-alt')" "1"
check "edit: malformed stdin exits 0 silently" "$(printf 'nope' | bash "$EDIT"; echo "exit $?")" "exit 0"
rm src/Bad.tsx

# --- hooks.json wiring ---
check "hooks.json registers the edit hook's matcher" "$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS")" "Edit|Write|MultiEdit"
check "hooks.json runs ui-edit-hook.sh" "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/ui-edit-hook.sh"'
check "hooks.json: the edit hook is synchronous, bash, 30 s" \
  "$(jq -r '.hooks.PostToolUse[0].hooks[0] | [.async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "false,bash,30"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: FAIL lines, exit 1.

- [ ] **Step 3: Write the hook**

Create `plugins/dforge/scripts/ui-edit-hook.sh`:

````bash
#!/usr/bin/env bash
# PostToolUse hook (Edit, Write, MultiEdit): when the edited file is a UI file
# (scripts/ui-proof paths), return scripts/ui-lint's findings as additional
# context, and on the first UI edit of a session that has not loaded
# dforge:ui-ux, name the skill once. It never blocks: it prints nothing or one
# hookSpecificOutput object, and always exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
file=$(jq -r '.tool_input.file_path // empty' <<<"$stdin_json")
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
[ -n "$file" ] || exit 0
file=${file//\\//}
case $file in /*|[A-Za-z]:/*) ;; *) file="${cwd:-$PWD}/$file" ;; esac
[ -f "$file" ] || exit 0
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "$SCRIPT_DIR/lib/ui-ux.sh"
rel=${file#"$root"/}
uiux_is_ui "$rel" "$(uiux_globs "$root")" || exit 0

lint=$(cd "$root" && bash "$SCRIPT_DIR/ui-lint" "$rel" 2>/dev/null)
remind=""
if [ -n "$session_id" ]; then
  marker="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-').ui-ux"
  if [ ! -f "$marker" ]; then
    { mkdir -p "$(dirname "$marker")" && : > "$marker"; } 2>/dev/null
    uiux_ran_skill "$transcript_path" ||
      remind="This edit changes a UI file (${rel}). Load dforge:ui-ux with the Skill tool: it owns UI/UX work, and the work is not done until it is proven in the running UI."
  fi
fi

text=""
if [ -n "$lint" ]; then
  text="dforge ui-lint, $(grep -c . <<<"$lint") finding(s) in ${rel}:
$(sed 's/^/- /' <<<"$lint")"
fi
if [ -n "$remind" ]; then text="${text:+$text

}$remind"; fi
[ -n "$text" ] || exit 0
jq -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $t}}'
exit 0
````

- [ ] **Step 4: Register the hook**

In `plugins/dforge/hooks/hooks.json`, add a `PostToolUse` key to the `hooks` object, between `"UserPromptSubmit": [...]` and `"Stop": [...]`:

```json
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/ui-edit-hook.sh\"",
            "shell": "bash",
            "async": false,
            "timeout": 30
          }
        ]
      }
    ],
```

Run `jq -e . plugins/dforge/hooks/hooks.json >/dev/null && echo valid`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/ui-hooks.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh
```
Expected: both end `0 failed`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/ui-edit-hook.sh plugins/dforge/hooks/hooks.json plugins/dforge/tests/ui-hooks.test.sh
git commit -m "feat(dforge): lint UI edits and name the ui-ux skill"
```

---

### Task 10: Add the Stop hold for unproven UI changes

**Files:**
- Create: `plugins/dforge/scripts/ui-turn-end.sh`
- Modify: `plugins/dforge/hooks/hooks.json`
- Test: `plugins/dforge/tests/ui-hooks.test.sh`
- Test: `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

**Interfaces:**
- Consumes: `scripts/lib/ui-ux.sh`, `scripts/ui-proof check` (Contracts); the turn stamp `.refs` from `scripts/turn-start.sh`
- Produces: the Stop hook (Contracts)

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/ui-hooks.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- Stop ---
END="$HERE/../scripts/ui-turn-end.sh"
START="$HERE/../scripts/turn-start.sh"
AR="$HERE/../scripts/auto-run"
prompt() { # prompt <session>
  jq -n --arg sid "$1" --arg cwd "$REPO" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"
}
stop() { # stop <session> <last message> [stop_hook_active] [transcript]
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg msg "$2" --argjson active "${3:-false}" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }

prompt s-1
printf '// change\n' >> src/App.tsx
git commit -q -am 'ui change'
check "stop: no profile and no skill run: passes" "$(stop s-1 'Done.')" ""

mkdir -p docs/dforge/ui-ux
printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
prompt s-2
printf '// change 2\n' >> src/App.tsx
git commit -q -am 'ui change 2'
out=$(stop s-2 'Done.')
check "stop: a committed UI change without proof is held" "$(decision "$out")" "block"
check "stop: the reason names the changed file" "$(jq -r .reason <<<"$out" | grep -c 'src/App.tsx')" "1"
check "stop: the reason names the pending line" "$(jq -r .reason <<<"$out" | grep -c 'UI proof: pending')" "1"
check "stop: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'dforge held the stop')" "1"
check "stop: the retry passes" "$(stop s-2 'Done.' true)" ""
check "stop: the pending line passes" "$(stop s-2 $'Done.\n\nUI proof: pending — no browser on this host')" ""
prompt s-3
check "stop: a turn that changed no UI file passes" "$(stop s-3 'Done.')" ""

mv docs/dforge/ui-ux/profile.md "$TMP/profile.md"
prompt s-4
printf '// change 3\n' >> src/App.tsx
check "stop: no profile but the skill ran: held" "$(decision "$(stop s-4 'Done.' false "$TR")")" "block"
check "stop: no profile and no skill: passes" "$(stop s-4 'Done.')" ""
mv "$TMP/profile.md" docs/dforge/ui-ux/profile.md

mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-5"
(cd "$REPO" && bash "$AR" --session s-5 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1)
prompt s-5
check "stop: an auto run bound to the session: passes" "$(stop s-5 'Done.')" ""
check "stop: another session in the checkout is still held" "$(decision "$(stop s-2 'Done.')")" "block"
check "stop: no stamp for the session: passes" "$(stop s-unknown 'Done.')" ""

check "hooks.json registers the UI Stop check once" \
  "$(jq -r '[.hooks.Stop[0].hooks[].command | select(contains("ui-turn-end.sh"))] | length' "$HOOKS")" "1"
check "hooks.json: the Stop check is synchronous, bash, 60 s" \
  "$(jq -r '.hooks.Stop[0].hooks[] | select(.command | contains("ui-turn-end.sh")) | [.async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "false,bash,60"
check "hooks.json: turn-end.sh stays the first Stop hook" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/turn-end.sh"'
check "hooks.json: the description names the UI hooks" "$(jq -r .description "$HOOKS" | grep -c 'UI proof')" "1"
````

In `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`, in the test titled `the hooks are bounded: SessionStart 300 seconds, Stop 120, …`, replace the line `  assert.deepEqual(more, []);` with:

```js
  const [uiTurnEnd, ...rest] = more;
  assert.match(uiTurnEnd.command, /scripts\/ui-turn-end\.sh/);
  assert.equal(uiTurnEnd.async, false);
  assert.equal(uiTurnEnd.timeout, 60);
  assert.deepEqual(rest, []);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: the new Stop cases print FAIL, exit 1.

- [ ] **Step 3: Write the hook**

Create `plugins/dforge/scripts/ui-turn-end.sh`:

````bash
#!/usr/bin/env bash
# Stop hook: a turn that leaves UI changes without a passing proof is held
# once. The changes are the UI files that differ from the commit this
# checkout's branch pointed at when the turn started (scripts/turn-start.sh
# records it), committed or not; a passing proof is `ui-proof check` exit 0.
# It applies only where the gate is on: the project has a UI profile, or the
# session ran dforge:ui-ux. It stands down while an auto run is bound to the
# session (turn-end.sh owns those stops), on the retry (stop_hook_active), and
# when the last message carries "UI proof: pending" with its reason. Anything
# missing (jq, the turn stamp, a branch head for this checkout) passes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
stdin_json="$(cat 2>/dev/null || true)"
jq -e . >/dev/null 2>&1 <<<"$stdin_json" || exit 0
session_id=$(jq -r '.session_id // empty' <<<"$stdin_json")
cwd=$(jq -r '.cwd // empty' <<<"$stdin_json")
transcript_path=$(jq -r '.transcript_path // empty' <<<"$stdin_json")
is_retry=$(jq -r '.stop_hook_active // false' <<<"$stdin_json")
[ -n "$session_id" ] || exit 0
[ "$is_retry" = true ] && exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
if (cd "$root" && bash "$SCRIPT_DIR/auto-run" --session "$session_id" pending >/dev/null 2>&1); then exit 0; fi

stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp.refs" ] || exit 0
base=$(tail -n +3 "$stamp.refs" | awk -F'\t' -v top="$root" 'stop { next } $2 == top { print $1; stop = 1 }')
[ -n "$base" ] || exit 0

. "$SCRIPT_DIR/lib/ui-ux.sh"
active=()
if [ ! -f "$(uiux_profile "$root")" ]; then
  uiux_ran_skill "$transcript_path" || exit 0
  active=(--active)
fi
last=$(jq -r '.last_assistant_message // empty' <<<"$stdin_json")
case $last in *'UI proof: pending'*) exit 0 ;; esac

out=$(cd "$root" && bash "$SCRIPT_DIR/ui-proof" check --base "$base" ${active[@]+"${active[@]}"} 2>&1)
status=$?
[ "$status" -eq 1 ] || exit 0

root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
reason="This turn leaves UI changes without a passing UI proof (dforge:ui-ux):
$out
Prove them before you say the work is done: run the dforge:ui-ux Prove phase (its references/walkthrough.md), stamp the report, record the judge's verdict, then run \`bash \"${root_shown}/scripts/ui-proof\" check --base ${base}\` again. If the proof cannot happen in this turn, end your message with the line \`UI proof: pending — <why>\` instead, so the user knows the UI is unproven."
jq -n --arg r "$reason" --arg m "dforge held the stop: UI files changed without a passing UI proof" \
  '{decision: "block", reason: $r, systemMessage: $m}'
exit 0
````

- [ ] **Step 4: Register the hook and update the description**

In `plugins/dforge/hooks/hooks.json`, append to the `Stop[0].hooks` array, after the `darkmem-stop-push.sh` entry:

```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/ui-turn-end.sh\"",
            "shell": "bash",
            "async": false,
            "timeout": 60
          }
```

and replace the end of the `description` string, `…ends without its sentinel line."`, with `…ends without its sentinel line; after an edit to a UI file it returns UI lint findings and names the ui-ux skill once per session, and it holds a stop once when a turn leaves UI changes without a passing UI proof."` Run `jq -e . plugins/dforge/hooks/hooks.json >/dev/null && echo valid`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/turn-end.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh
```
Expected: each ends with no failure, exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/ui-turn-end.sh plugins/dforge/hooks/hooks.json plugins/dforge/tests/ui-hooks.test.sh plugins/dforge/tests/darkmem-sync/hooks.test.mjs
git commit -m "feat(dforge): hold stops that leave UI unproven"
```

---

### Task 11: Teach plan-lint the UI/UX line

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint`
- Test: `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: `uiux_contract_ids`, `uiux_globs`, `uiux_is_ui` (Contracts)
- Produces: the plan-lint findings for the `**UI/UX:**` line (Contracts)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/plan-lint.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- UI/UX contract (dforge:ui-ux) ---
cat > docs/ui-spec.md <<'EOF'
# Spec

## UI/UX contract

**UI/UX depth:** feature — a dialog

- **UI-1** — Dialog layout.
- **UX-1** — Escape closes the dialog.
- **UX-2** — Focus returns to the trigger.
- **OP-1** — Proven at 375 and 1440.
EOF
ui_plan() { # ui_plan <Task 1 UI/UX line or empty> <Task 2 UI/UX line or empty>
  cat <<EOF
# UI Plan

**Goal:** Demo.

**Spec:** \`docs/ui-spec.md\`

**Execution:** inline — \`claude --model sonnet --effort low\` — small

## Global Constraints

None.

## Contracts

None.

## Assumptions (evidence)

None.

## Task index

1. Dialog
2. Docs

### Task 1: Dialog

**Files:**
- Modify: \`src/Dialog.tsx\`

$1

### Task 2: Docs

**Files:**
- Modify: \`README.md\`

$2
EOF
}
ui_plan '' '' > ui-bad.md
out=$(bash "$LINT" ui-bad.md --no-probe 2>&1)
has "ui: a UI task without a UI/UX line" "$out" "ERROR Task 1: touches the UI file src/Dialog.tsx but has no **UI/UX:** line"
has "ui: an uncited UI item" "$out" "ERROR header: UI/UX contract item UI-1 is named by no task's **UI/UX:** line"
lacks "ui: an OP item needs no task" "$out" "item OP-1 is named by no task"
lacks "ui: a non-UI task needs no line" "$out" "ERROR Task 2: touches the UI file"
ui_plan '**UI/UX:** UI-1, UX-1, UX-9' '' > ui-undef.md
out=$(bash "$LINT" ui-undef.md --no-probe 2>&1)
has "ui: an undefined ID" "$out" "ERROR Task 1: **UI/UX:** cites UX-9, which the spec's UI/UX contract does not define"
has "ui: an item no task names" "$out" "item UX-2 is named by no task"
ui_plan '**UI/UX:** UI-1, UX-1' '**UI/UX:** UX-2' > ui-good.md
out=$(bash "$LINT" ui-good.md --no-probe 2>&1)
lacks "ui: a covered plan has no UI/UX finding" "$out" "UI/UX"
sed 's#docs/ui-spec.md#docs/spec.md#' ui-bad.md > ui-nocontract.md
out=$(bash "$LINT" ui-nocontract.md --no-probe 2>&1)
lacks "ui: a spec without a contract asks for no line" "$out" "UI/UX"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 900 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: the four `has` cases above FAIL, exit 1.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/plan-lint`, insert directly above the line `cat "$findings"` near the end:

````bash
# --- UI/UX contract (dforge:ui-ux) ---
# A spec with a "## UI/UX contract" makes every task that touches a UI file
# name the contract items it delivers, and every UI- and UX- item reach some
# task. OP- items describe the whole result: they are proven, not built.
if [ -n "${spec_path:-}" ]; then
  . "$HERE/lib/ui-ux.sh"
  ui_spec=$(dforge_resolve "$spec_path" "$root")
  ui_ids=""
  [ ! -f "$ui_spec" ] || ui_ids=$(uiux_contract_ids "$ui_spec")
  if [ -n "$ui_ids" ]; then
    ui_globs=$(uiux_globs "$root")
    ui_cited=""
    for n in $nums; do
      ui_text=$(plan_task_text "$src" "$n")
      ui_line=$(plan_lines 'UI/UX' <<<"$ui_text" | head -n 1)
      ui_task_ids=$(grep -oE '(UI|UX|OP)-[0-9]+' <<<"$ui_line" || true)
      ui_cited="$ui_cited$ui_task_ids"$'\n'
      for id in $ui_task_ids; do
        grep -qxF "$id" <<<"$ui_ids" \
          || say ERROR "Task $n" "**UI/UX:** cites $id, which the spec's UI/UX contract does not define"
      done
      [ -z "$ui_line" ] || continue
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        if uiux_is_ui "$path" "$ui_globs"; then
          say ERROR "Task $n" "touches the UI file $path but has no **UI/UX:** line naming the contract items it delivers"
          break
        fi
      done < <(plan_task_paths <<<"$ui_text")
    done
    while IFS= read -r id; do
      case $id in UI-*|UX-*) ;; *) continue ;; esac
      grep -qxF "$id" <<<"$ui_cited" \
        || say ERROR header "UI/UX contract item $id is named by no task's **UI/UX:** line"
    done <<<"$ui_ids"
  fi
fi

````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 900 bash plugins/dforge/tests/plan-lint.test.sh`
Expected: `0 failed`, exit 0 (every earlier case still passes).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/plan-lint plugins/dforge/tests/plan-lint.test.sh
git commit -m "feat(dforge): check UI/UX lines in plan-lint"
```

---

### Task 12: Append contract items to UI task briefs

**Files:**
- Modify: `plugins/dforge/scripts/task-brief`
- Test: `plugins/dforge/tests/budget-line.test.sh`

**Interfaces:**
- Consumes: `uiux_items` (Contracts)
- Produces: the `## UI/UX contract items` brief section (Contracts)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/budget-line.test.sh`, directly above its final `printf '\n%d passed…` line (the suite's working directory is its temporary repository, which has `docs/`):

````bash
# --- UI/UX contract items (dforge:ui-ux) ---
cat > docs/ui-spec.md <<'EOF'
# Spec

## UI/UX contract

**UI/UX depth:** feature — a dialog

- **UX-1** — Escape closes the dialog.
  Focus returns to the trigger.
- **UX-2** — The dialog traps focus.
EOF
cat > docs/ui-plan.md <<'EOF'
# Plan

**Spec:** `docs/ui-spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — x

## Global Constraints

- Bash only.

## Contracts

- None.

## Task index

1. Dialog
2. Docs

### Task 1: Dialog

**UI/UX:** UX-1

Build the dialog.

### Task 2: Docs

Write the docs.
EOF
bash "$P/scripts/task-brief" docs/ui-plan.md 1 "$TMP/ui1.md" >/dev/null 2>&1
check "task-brief: a UI task's brief carries the items heading" "$(grep -c '^## UI/UX contract items$' "$TMP/ui1.md")" "1"
check "task-brief: the cited item, verbatim with its continuation" \
  "$(grep -c -e '^- \*\*UX-1\*\* — Escape closes the dialog\.$' -e '^  Focus returns to the trigger\.$' "$TMP/ui1.md")" "2"
check "task-brief: an uncited item is left out" "$(grep -c 'UX-2' "$TMP/ui1.md")" "0"
check "task-brief: the items come after the excerpt" \
  "$([ "$(grep -n '^## UI/UX contract items$' "$TMP/ui1.md" | cut -d: -f1)" -gt "$(grep -n '^## Plan header excerpt$' "$TMP/ui1.md" | cut -d: -f1)" ] && echo yes || echo no)" "yes"
bash "$P/scripts/task-brief" docs/ui-plan.md 2 "$TMP/ui2.md" >/dev/null 2>&1
check "task-brief: a task without a UI/UX line gets no items" "$(grep -c 'UI/UX contract items' "$TMP/ui2.md")" "0"
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/budget-line.test.sh`
Expected: the new cases FAIL, exit 1.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/task-brief`, directly after the block that appends the excerpt — the lines

```bash
  if [ -n "$excerpt" ]; then
    printf '\n## Plan header excerpt\n\n%s\n' "$excerpt" >> "$out"
  fi
```

and before the `fi` that closes the `else` branch — insert:

````bash
  # dforge:ui-ux — a UI task's brief carries the contract items it delivers,
  # verbatim from the spec, so the implementer builds the states and
  # behaviour, not only the layout.
  ui_line=$(plan_task_text "$src" "$n" | plan_lines 'UI/UX' | head -n 1)
  if [ -n "$ui_line" ]; then
    . "$HERE/lib/ui-ux.sh"
    ui_spec=$(plan_header_line "$src" Spec | sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/')
    ui_file=$(dforge_resolve "$ui_spec" "$(_plan_ctx "$plan")")
    ui_ids=$( { grep -oE '(UI|UX|OP)-[0-9]+' <<<"$ui_line" || true; } | tr '\n' ' ')
    ui_items=""
    # shellcheck disable=SC2086
    [ ! -f "$ui_file" ] || ui_items=$(uiux_items "$ui_file" "UI/UX contract" $ui_ids)
    printf '\n## UI/UX contract items\n\nFrom `%s`, verbatim. Build every state, behaviour and promise below, render the result through the project UI profile'"'"'s harness before you report, and map each ID to its evidence (a screenshot path or a test name) in your report.\n\n%s\n' \
      "$ui_spec" "${ui_items:-(the spec defines none of: $ui_ids)}" >> "$out"
  fi
````

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/budget-line.test.sh`
Expected: `0 failed`, exit 0 (the existing "brief ends with Contracts" case uses a plan without a UI/UX line and still passes).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-brief plugins/dforge/tests/budget-line.test.sh
git commit -m "feat(dforge): carry contract items into UI briefs"
```

---

### Task 13: Add the ui-ux review lens

**Files:**
- Create: `plugins/dforge/criteria/lenses/ui-ux.md`
- Modify: `plugins/dforge/scripts/lens-route`
- Modify: `plugins/dforge/reference/native-codex.md`
- Test: `plugins/dforge/tests/lens-route.test.sh`
- Test: `plugins/dforge/tests/criteria.test.sh`

**Interfaces:**
- Consumes: `uiux_globs`, `uiux_is_ui`, `uiux_profile`, `uiux_contract_ids` (Contracts)
- Produces: the `ui-ux` lens and the `ui-paths` clause (Contracts)

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/criteria.test.sh`:
- change the clause check `grep -cvE '^(always|paths [^ ].*|added .+)$'` to `grep -cvE '^(always|ui-paths|paths [^ ].*|added .+)$'`;
- change the lens-list check to:

```bash
check "the lenses exist" "$got" \
  "docs-comments lang-bash lang-csharp lang-python lang-typescript security silent-failures test-quality type-design ui-ux"
```

In `plugins/dforge/tests/lens-route.test.sh`, change `short()` so it strips the new reason too:

```bash
short() { sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'; }
```

and insert directly above its final `printf '\n%d passed…` line:

````bash
# --- the ui-ux lens (dforge:ui-ux) ---
UIR="$TMP/uirepo"
git init -q "$UIR" && cd "$UIR" || exit 1
git config user.email t@example.com && git config user.name t
git commit -q --allow-empty -m base
UBASE=$(git rev-parse HEAD)
sed 's/^|//' > plan.md <<'EOF'
|# UI Fixture Plan
|
|## Task index
|
|1. ui
|
|### Task 1: ui
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
EOF
mkdir -p src tests
printf 'const v = a ?? b;\n' > src/App.tsx
printf 'test("x", () => {});\n' > tests/app.test.ts
git add src tests && git commit -q -m ui
UHEAD=$(git rev-parse HEAD)
uroute() { HOME="$TMP/uihome" bash "$ROUTE" "$@"; }
out=$(uroute plan.md --final "$UBASE" "$UHEAD")
check "ui-ux: no profile and no contract: not routed" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens lang-typescript;"
mkdir -p docs/dforge/ui-ux && printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
out=$(uroute plan.md --final "$UBASE" "$UHEAD")
check "ui-ux: with a profile it is second and survives the default cap" "$(short <<<"$out")" \
  "lens security;lens ui-ux;lens silent-failures;lens test-quality;lens-skipped lang-typescript reason=cap;"
check "ui-ux: the reason" "$(grep -c '^lens ui-ux .* reason=ui-paths$' <<<"$out")" "1"
rm docs/dforge/ui-ux/profile.md
printf '# Spec\n\n## UI/UX contract\n\n**UI/UX depth:** feature — x\n\n- **UX-1** — Escape closes the dialog.\n' > docs/s.md
{ printf '**Spec:** `docs/s.md`\n\n'; cat plan.md; } > plan-spec.md
out=$(uroute plan-spec.md --final "$UBASE" "$UHEAD")
check "ui-ux: a plan whose spec has a contract routes it" "$(grep -c '^lens ui-ux ' <<<"$out")" "1"
printf 'echo hi\n' > run.sh && git add run.sh && git commit -q -m sh
U2=$(git rev-parse HEAD)
out=$(uroute plan-spec.md --final "$UHEAD" "$U2")
check "ui-ux: no UI file changed: not routed" "$(grep -c '^lens ui-ux ' <<<"$out")" "0"
printf '# T\n\n## Task index\n\n1. r\n\n### Task 1: r\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n**Lenses:** ui-ux\n' > plan-task.md
check "ui-ux: a risk-3 task may name the lens" "$(uroute plan-task.md --task 1 | sed -E 's/ criteria=[^ ]*//')" "lens ui-ux"
````

- [ ] **Step 2: Run the tests to verify they fail**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/lens-route.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/criteria.test.sh
```
Expected: the new cases FAIL, exit 1 for both.

- [ ] **Step 3: Write the lens**

Create `plugins/dforge/criteria/lenses/ui-ux.md` with exactly (ASCII only):

````markdown
# UI/UX Lens - Review Criteria

Applies: ui-paths

A review lens, not a scored rubric: report each hit as a finding tagged
[lens:ui-ux] at your own severity.

## Ground Truth Note

Judge the UI the user will meet, not the main path the diff was written for.
When the plan's spec has a "## UI/UX contract", read it first: an item the
diff should build and does not is a finding. scripts/ui-lint findings already
reach the implementer; look for what a single-line pattern cannot see.

## Criteria

### Missing States {#states}

Look at every component, screen and data fetch the diff adds or changes.
Report a finding when a data state (loading, empty, error, partial, offline,
permission denied, very long or very large content) or a control state
(hover, keyboard focus, active, disabled, pending, invalid) has no rendering,
or when a pending action can be submitted twice.

### Keyboard and Assistive Access {#access}

Look at interactive elements, dialogs, menus and custom controls. Report a
finding for an action reachable only by pointer, a control without an
accessible name, focus that is lost or not returned after a dialog closes or
an item is deleted, a focus trap with no exit, motion without a
reduced-motion fallback, or state conveyed by colour alone.

### Design System Bypass {#tokens}

Look at styles, class names and component choices. Report a finding for a
raw colour, size or spacing value where the design system has a token, a
hand-built control where the design system has a component, or a variant
built from overrides instead of the component's own variant.

### Feedback and Forms {#feedback}

Look at forms, buttons that start work, and destructive actions. Report a
finding when validation fires at the wrong time or never, an error does not
say what happened and how to fix it, input is lost after an error, a slow
action shows no progress, or a destructive action has neither a confirmation
naming what it destroys nor an undo.
````

- [ ] **Step 4: Route it**

In `plugins/dforge/scripts/lens-route`:

1. In `lens_order`, change the leader loop and the fallback exclusion to:

```bash
  for id in security ui-ux silent-failures test-quality; do grep -qxF "$id" <<<"$all" && echo "$id"; done
```
```bash
  grep -vxE 'security|ui-ux|silent-failures|test-quality|type-design|docs-comments|lang-.*' <<<"$all"
```

and update the comment above `lens_order` to read `# lens_order — every lens id, highest priority first: four fixed leaders (security, then ui-ux, so the cap keeps the UI lens on a UI branch), the language lenses alphabetically, two fixed trailers, then any other lens.`

2. In `lens_match`, add an arm to the `case $kind in` block, before `added)`:

```bash
      ui-paths)
        [ "${ui_active:-0}" = 1 ] || continue
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          if uiux_is_ui "$f" "$ui_globs"; then echo ui-paths; return 0; fi
        done <<<"$changed" ;;
```

and extend its header comment with: `A ui-paths clause matches a changed UI file (scripts/ui-proof paths) only when the project has a UI profile or the plan's spec has a UI/UX contract.`

3. In the `--final)` arm, directly after the line `added=$(git diff -U0 …)`, insert:

```bash
    # dforge:ui-ux — the UI lens applies where the UI gate does.
    . "$HERE/lib/ui-ux.sh"
    ui_top=$(git rev-parse --show-toplevel)
    ui_globs=$(uiux_globs "$ui_top") ui_active=0
    [ ! -f "$(uiux_profile "$ui_top")" ] || ui_active=1
    ui_spec_line=$(plan_header_line "$src" Spec)
    if [ "$ui_active" = 0 ] && [ -n "$ui_spec_line" ]; then
      ui_spec=$(sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/' <<<"$ui_spec_line")
      ui_spec=$(dforge_resolve "$ui_spec" "$ui_top")
      [ ! -f "$ui_spec" ] || [ -z "$(uiux_contract_ids "$ui_spec")" ] || ui_active=1
    fi
```

4. In the usage comment at the top, change `reason=<always|paths:<glob>|added>` to `reason=<always|paths:<glob>|added|ui-paths>`.

- [ ] **Step 5: Update the Codex reference**

In `plugins/dforge/reference/native-codex.md`, change `(security, silent-failures, test-quality, the `lang-*` lenses` to `(security, ui-ux, silent-failures, test-quality, the `lang-*` lenses`, and after the sentence that ends `skipped in the report.` (it wraps across two lines) add: ``An `Applies: ui-paths` clause matches a changed file that `scripts/ui-proof paths` lists, and only when the project has a UI profile (`<docs>/ui-ux/profile.md`) or the plan's spec has a `## UI/UX contract`.``

- [ ] **Step 6: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/lens-route.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 120 bash plugins/dforge/tests/criteria.test.sh
```
Expected: both `0 failed`, exit 0; every earlier lens-route case keeps its output (their fixture has no profile and no spec).

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/criteria/lenses/ui-ux.md plugins/dforge/scripts/lens-route plugins/dforge/reference/native-codex.md plugins/dforge/tests/lens-route.test.sh plugins/dforge/tests/criteria.test.sh
git commit -m "feat(dforge): add the ui-ux review lens"
```

---

### Task 14: Gate the final review, finishing and done claims

**Files:**
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dforge/skills/verification-before-completion/SKILL.md`
- Test: `plugins/dforge/tests/ui-ux-skill.test.sh`

**Interfaces:**
- Consumes: `ui-proof check` (Contracts); the skill from Task 8
- Produces: the three gate sites (spec §The gate)

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/ui-ux-skill.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- the gate sites ---
FR="$P/reference/final-review.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
VBC="$P/skills/verification-before-completion/SKILL.md"
names "final review runs the gate" "$FR" 'scripts/ui-proof check --base MERGE_BASE --spec <the plan'"'"'s Spec>'
names "final review: exit 1 stops it like a red gate" "$FR" 'Exit 1 stops the review like a red gate'
names "final review: the auto-run path proves, then checks again" "$FR" 'phase, then check again, and go on when it passes'
names "final review: only an unverifiable row stops an auto run" "$FR" 'auto-run stop --reason "ui proof needs the user"'
names "final review: the check runs again after the fix wave" "$FR" 'step 0.2'"'"'s `ui-proof check` again'
names "finishing runs the gate" "$FIN" 'scripts/ui-proof check --base'
names "finishing: exit 1 keeps a recorded merge or pr" "$FIN" 'turns a recorded `merge` or `pr` into `keep`'
names "finishing: the two-option prompt ends on the menu line" "$FIN" '1. Prove it first'
names "finishing: Step 4 keeps a recorded merge after an unproven UI" "$FIN" 'When Step 1b'"'"'s `ui-proof check` exited 1, `merge` and `pr` become `keep`'
names "finishing: the auto-run mapping keeps too" "$FIN" '`merge` and `pr` also keep when Step 1b'"'"'s `ui-proof check` exited 1'
names "finishing: an auto run stops for unverifiable rows" "$FIN" 'auto-run stop --reason "ui proof needs the user"'
names "final review: step 0 goes on to step 0.2" "$FR" 'say so in one line and go to step 0.2'
names "verification: the UI claim row" "$VBC" '| The UI works |'
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: the thirteen new checks FAIL, exit 1.

- [ ] **Step 3: Edit the final review**

In `plugins/dforge/reference/final-review.md`, insert directly above the line that begins `- 0.5 **Acceptance QA.**`:

```markdown
- 0.2 **UI proof.** Run
  `bash <plugin-root>/scripts/ui-proof check --base MERGE_BASE --spec <the plan's Spec>`
  under `timeout 120`. Exit 0 goes on (it also prints `ok` when the project
  has no UI profile and the spec no UI/UX contract, or when no UI file
  changed). Exit 1 stops the review like a red gate: the UI is unproven, and
  reviewing it spends the seats on what the proof would have found. Attended,
  report the failed steps and stop. In an auto run, run the dforge:ui-ux Prove
  phase, then check again, and go on when it passes; when the second exit 1
  comes only from `unverifiable` rows, which need the user's words, run
  `scripts/auto-run stop --reason "ui proof needs the user"` and end as
  auto-run.md §Stopping says; any other second exit 1 is the first finding on
  the fix wave's list.
```

In step 0's text, change `say so in one line and go to step 0.5.` to `say so in one line and go to step 0.2.`, and in the `## The review` paragraph change `Step 0 runs first.` to `Step 0 runs first, then step 0.2.`

In its `## Fixing what it finds` section, add this paragraph after the paragraph that begins `If confirmed findings remain, fix them in ONE wave`:

```markdown
The fix wave edits UI files and so stales the UI proof: after the wave, run
step 0.2's `ui-proof check` again. Exit 1 then means the dforge:ui-ux Prove
phase again in an auto run, and attended, a stop that reports the failed
steps.
```

- [ ] **Step 4: Edit finishing**

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, change `**If tests pass:** continue to Step 2.` to `**If tests pass:** continue to Step 1b.`, and insert directly above `## Step 2: Detect Environment`:

````markdown
## Step 1b: Prove the UI

Run, under `timeout 120`, with the branch this one was created from (Step 3
explains how to find it; determine it now) as `<base branch>`:

```bash
bash <plugin-root>/scripts/ui-proof check --base "$(git merge-base HEAD <base branch>)" --spec <the plan's Spec>
```

Drop `--spec` when there is no plan. **Exit 0** (it also prints `ok` when the
gate is off or no UI file changed): continue to Step 2.

**Exit 1:** the UI is unproven, and integrating it is blocked. In an auto
run, first run the dforge:ui-ux Prove phase and check again; only that second
exit 1 counts, and when it comes only from `unverifiable` rows, run
`scripts/auto-run stop --reason "ui proof needs the user"` first. Remember the
exit 1 for Step 4: it turns a recorded `merge` or `pr` into `keep`. Run
`scripts/finish-choice get [--plan PLAN_FILE]` now: when it prints `merge`,
`pr` or `keep`, or an auto run is bound, continue to Step 2 (Step 4 keeps the
branch). Otherwise present only these two options:

```
The UI is unproven (ui-proof check):
<its FAIL lines>

1. Prove it first — run the dforge:ui-ux Prove phase, then return to Step 1b
2. Keep the branch as-is (I'll handle it later)

Which option?
```
````

Then make the two Step 4 edits:

1. In `## Step 4: Present Options`, find the bullet that begins with the text below, and add the sentence after it on the same bullet, right after `show no menu.`:

   Bullet begins:
   ```text
   - It prints `merge`, `pr` or `keep` with no `answer` or `firedAt` field: show
     no menu.
   ```
   Sentence to add:
   ```text
   When Step 1b's `ui-proof check` exited 1, `merge` and `pr` become `keep`: say so, and that the UI is unproven.
   ```

2. In `## Auto run`, in the **Step 4 shows no menu** bullet, add this sentence directly after the sentence that ends `Note is` followed by `` `final review residual`. ``:
   ```text
   `merge` and `pr` also keep when Step 1b's `ui-proof check` exited 1 after the Prove re-run.
   ```

- [ ] **Step 5: Edit verification-before-completion**

In `plugins/dforge/skills/verification-before-completion/SKILL.md`, add this row to the claims table, directly below the `| Requirements met | … |` row:

```markdown
| The UI works | `scripts/ui-proof check --base <branch base>` (plus `--spec`): exit 0 | Screenshots in chat, tests passing, "looks right" |
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/final-phase.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/finish-choice.test.sh
timeout 60 node scripts/validate-repository.mjs
```
Expected: every suite `0 failed`, validate exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/reference/final-review.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/skills/verification-before-completion/SKILL.md plugins/dforge/tests/ui-ux-skill.test.sh
git commit -m "feat(dforge): gate review and finishing on UI proof"
```

---

### Task 15: Route UI work to the skill

**Files:**
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md`
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Modify: `plugins/dforge/skills/systematic-debugging/SKILL.md`
- Test: `plugins/dforge/tests/ui-ux-skill.test.sh`

**Interfaces:**
- Consumes: the skill from Task 8
- Produces: the routing (spec §Integration edits)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/ui-ux-skill.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- routing ---
ENTRY="$P/skills/using-dforge/SKILL.md"
names "the entry point routes UI work" "$ENTRY" '| Anything a user sees or does | dforge:ui-ux |'
check "the entry point stays within 5100 bytes" "$([ "$(wc -c < "$ENTRY")" -le 5100 ] && echo yes || echo no)" "yes"
names "brainstorming runs Shape before acceptance" "$P/skills/brainstorming/SKILL.md" 'invoke dforge:ui-ux before drafting acceptance'
names "debugging runs touch depth for UI fixes" "$P/skills/systematic-debugging/SKILL.md" 'Run `dforge:ui-ux` at touch depth'
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: the routing checks FAIL (the size check passes), exit 1.

- [ ] **Step 3: Edit the entry point**

In `plugins/dforge/skills/using-dforge/SKILL.md`, make exactly these four edits:
1. Add the row `| Anything a user sees or does | dforge:ui-ux |` directly below `| Building or changing behaviour | dforge:brainstorming |`.
2. Change `if it has a checklist, create a todo per item.` to `a checklist gets a todo per item.`
3. Change `When the darkmem MCP is configured, prefer its` to `With the darkmem MCP, prefer its`.
4. Change `- No todo tool? Use the ledger or a checklist.` to `- No todo tool? Use the ledger.`

Run `wc -c plugins/dforge/skills/using-dforge/SKILL.md`. Expected: 5095 (at most 5100).

- [ ] **Step 4: Edit brainstorming**

In `plugins/dforge/skills/brainstorming/SKILL.md`, under `**Understanding the idea:**`, insert this bullet directly after the bullet that begins ``- Read `<docs>/distilled/constraints.md` `` (after its last line):

```markdown
- When the design has a user-facing part — anything a user sees or does —
  invoke dforge:ui-ux before drafting acceptance: its Shape phase writes the
  spec's `## UI/UX contract`, the source of every UI acceptance statement.
  Under `autoRun=on`, ask its profile and state-board questions among your
  clarifying questions.
```

- [ ] **Step 5: Edit systematic-debugging**

In `plugins/dforge/skills/systematic-debugging/SKILL.md`, Phase 4, add this bullet as the last bullet of item `3. **Verify Fix**` (after `- Use the `dforge:verification-before-completion` skill before claiming success`):

```markdown
   - Fix changes anything a user sees or does? Run `dforge:ui-ux` at touch depth: its delta and proof come before you claim the bug fixed
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
timeout 60 node scripts/validate-repository.mjs
```
Expected: every suite `0 failed`, validate exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/skills/systematic-debugging/SKILL.md plugins/dforge/tests/ui-ux-skill.test.sh
git commit -m "feat(dforge): route UI work to the ui-ux skill"
```

---

### Task 16: Document the UI/UX line for plans and seats

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/reference/delegated-task.md`
- Modify: `plugins/dforge/reference/acceptance-qa.md`
- Test: `plugins/dforge/tests/ui-ux-skill.test.sh`

**Interfaces:**
- Consumes: the `**UI/UX:**` line and brief section (Contracts)
- Produces: the plan-writer, dispatch and QA instructions (spec §Carry, A21)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Insert into `plugins/dforge/tests/ui-ux-skill.test.sh`, directly above its final `printf '\n%d passed…` line:

````bash
# --- plans, dispatch and QA ---
names "writing-plans documents the UI/UX line" "$P/skills/writing-plans/SKILL.md" '**UI/UX:** [only when the spec has a `## UI/UX contract`'
names "dispatch names render-before-report for UI tasks" "$P/reference/delegated-task.md" 'a brief that carries `## UI/UX contract items` is a UI task'
names "QA writes contract-ID statements for the UI test runner" "$P/reference/acceptance-qa.md" 'is written for the UI test runner the project'"'"'s UI profile names'
````

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: the three new checks FAIL, exit 1.

- [ ] **Step 3: Edit writing-plans**

In `plugins/dforge/skills/writing-plans/SKILL.md`, inside the Task Structure template, insert directly after the `**Items:** [...]` paragraph (before `**Depends on:**`):

```markdown
**UI/UX:** [only when the spec has a `## UI/UX contract` and the task's Files
match `scripts/ui-proof paths`: the contract IDs this task delivers, for
example `UI-2, UX-4`. Every `UI-` and `UX-` ID must reach some task; `OP-` IDs
are proven, not built. `plan-lint` checks both, and `task-brief` appends the
cited items to the brief (dforge:ui-ux).]
```

- [ ] **Step 4: Edit delegated-task**

In `plugins/dforge/reference/delegated-task.md`, §1, insert directly after the bullet that begins `- **Report file:**` (after its last line):

```markdown
- **UI tasks:** a brief that carries `## UI/UX contract items` is a UI task
  (dforge:ui-ux). Say in the dispatch that the implementer renders the result
  through the project UI profile's harness before reporting, and that the
  report maps each cited ID to a screenshot path or a test name; a cited ID
  with no evidence is a spec ❌ at review.
```

- [ ] **Step 5: Edit acceptance-qa**

In `plugins/dforge/reference/acceptance-qa.md`, append to the end of Procedure item `2. **Where tests live.**` (after its last sentence):

```markdown
   A statement whose text starts with a contract ID (`UI-<n>`, `UX-<n>`,
   `OP-<n>`) is written for the UI test runner the project's UI profile names
   (`<docs>/ui-ux/profile.md`, its `**UI test runner:**` line), driving the
   running UI through it.
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 60 bash plugins/dforge/tests/ui-ux-skill.test.sh
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 900 bash plugins/dforge/tests/plan-lint.test.sh
timeout 60 node scripts/validate-repository.mjs
```
Expected: `0 failed` for both suites (the template's `**UI/UX:**` line sits inside a fence, which plan-lint ignores), validate exit 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/reference/delegated-task.md plugins/dforge/reference/acceptance-qa.md plugins/dforge/tests/ui-ux-skill.test.sh
git commit -m "docs(dforge): carry the UI/UX line into plans"
```

---

### Task 17: Describe the skill in the README and manifests

**Files:**
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: everything above
- Produces: None

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Edit the README**

In `plugins/dforge/README.md`:
1. Under `## What you get`, append this paragraph after the last existing paragraph of that section:

```markdown
**UI/UX work proven in the running UI.** `dforge:ui-ux` turns a design into a
numbered UI/UX contract (UI, UX and an Output promise) in the spec,
`plan-lint` makes every UI task name the items it delivers, `task-brief`
hands them to the implementer verbatim, and a walkthrough proves each one on
the running UI — web, Windows, Linux desktop, Android or terminal — with a
judge seat reading the screenshots. `scripts/ui-proof check` blocks the final
review, finishing and every "done" claim until the proof covers the current
UI files.
```

2. Under `## How it fires`, append:

```markdown
A `PostToolUse` hook on `Edit`, `Write` and `MultiEdit` runs
`scripts/ui-edit-hook.sh`: for a UI file (`scripts/ui-proof paths`) it
returns `scripts/ui-lint` findings as additional context and, once per
session, names `dforge:ui-ux`; it never blocks. A third `Stop` hook,
`scripts/ui-turn-end.sh`, holds a turn once when it leaves UI changes without
a passing `ui-proof check` in a project with a UI profile (or a session that
ran the skill); the line `UI proof: pending — <why>` releases it, and it
stands down while an auto run is bound.
```

3. Under `## Tests`, append: ``The ui-ux suites — `ui-proof.test.sh`, `ui-lint.test.sh` (one failing and one passing fixture per rule), `ui-hooks.test.sh` and `ui-ux-skill.test.sh` — run against temporary repositories and the skill text.``

- [ ] **Step 2: Edit the manifests**

In both `plugins/dforge/.claude-plugin/plugin.json` and `plugins/dforge/.codex-plugin/plugin.json`, change the `description` value's `criteria-based review and an external Codex executor;` to `criteria-based review, UI/UX work proven in the running UI and an external Codex executor;`. In `.claude-plugin/plugin.json` add `"ui-ux"` to `keywords` after `"verification"`.

- [ ] **Step 3: Validate and commit**

```bash
timeout 60 node scripts/validate-repository.mjs
timeout 120 /root/.local/bin/claude plugin validate plugins/dforge
timeout 120 /root/.local/bin/claude plugin validate .
git add plugins/dforge/README.md plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json
git commit -m "docs(dforge): describe the ui-ux skill"
```
Expected: each validation passes.

---

### Task 18: Run the walkthrough and terminal demos

**Files:**
- Create: `plugins/dforge/tests/fixtures/ui-ux/walkthrough.html`
- Create: `docs/dforge/notes/2026-10-24-ui-ux-demos.md`
- Modify: `plugins/dforge/skills/ui-ux/references/platforms/terminal.md`

**Interfaces:**
- Consumes: the walkthrough and terminal guide (Task 7)
- Produces: the A20 and A17 (terminal) demo evidence

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the fixture page**

Create `plugins/dforge/tests/fixtures/ui-ux/walkthrough.html`:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Walkthrough fixture</title>
<style>
  :root { --surface: #ffffff; --text: #1a1a1a; --ring: #1a56db; }
  body { font: 16px/1.5 system-ui, sans-serif; margin: 2rem; background: var(--surface); color: var(--text); }
  button:focus-visible { outline: 3px solid var(--ring); outline-offset: 2px; }
  dialog { max-width: 28rem; }
</style>
</head>
<body>
<h1>Rename project</h1>
<button id="open" type="button">Rename</button>
<dialog id="dlg" aria-labelledby="dlg-title">
  <h2 id="dlg-title">Rename project</h2>
  <label for="name">Project name</label>
  <input id="name" autocomplete="off">
  <p id="err" role="alert" hidden>Enter a name of 1 to 64 characters.</p>
  <button id="save" type="button">Save name</button>
  <button id="cancel" type="button">Cancel</button>
</dialog>
<script>
  const dlg = document.getElementById('dlg'), open = document.getElementById('open');
  open.addEventListener('click', () => { dlg.showModal(); document.getElementById('name').focus(); });
  document.getElementById('cancel').addEventListener('click', () => dlg.close());
  dlg.addEventListener('close', () => open.focus());
  document.getElementById('save').addEventListener('click', () => {
    const v = document.getElementById('name').value.trim();
    document.getElementById('err').hidden = v.length > 0 && v.length <= 64;
    if (!document.getElementById('err').hidden) { document.getElementById('name').focus(); return; }
    dlg.close();
  });
</script>
</body>
</html>
```

- [ ] **Step 2: Run the web walkthrough from an implementer subagent (A20)**

Dispatch `dforge:impl-sonnet-low` with this prompt (fill `<WT>` with `git rev-parse --show-toplevel`):

```
Capability demo, not a code task: edit and commit nothing.
Follow <WT>/plugins/dforge/skills/ui-ux/references/walkthrough.md steps 3, 4 and 6 and platforms/web.md against
file://<WT>/plugins/dforge/tests/fixtures/ui-ux/walkthrough.html (if file:// is refused, serve the directory with
`timeout 600 python3 -m http.server 8765 --directory <WT>/plugins/dforge/tests/fixtures/ui-ux` as a background task, use
http://127.0.0.1:8765/walkthrough.html, and kill the server when done).
At 375x812 and at 1440x900: (1) keyboard only — Tab to "Rename", Enter opens the dialog, focus is on the name field,
Escape closes it and focus returns to "Rename" (confirm each with browser_snapshot's [active] marker); (2) Enter an empty
name and press "Save name": the error shows and focus stays on the field.
Save screenshots by absolute path under <WT>/.dforge/ui-ux/demo/ named ux-1-<viewport>-light.png (dialog open) and
ux-2-<viewport>-light-error.png. Close the browser. Report each check's result and every file path you wrote.
```

Then verify: `ls -l <WT>/.dforge/ui-ux/demo/*.png` shows four files, and open one with the Read tool.

- [ ] **Step 3: Run the terminal guide (A17, terminal half)**

```bash
timeout 30 tmux new-session -d -s uiux -x 80 -y 24 'bash --norc -i'
timeout 10 tmux send-keys -t uiux 'select c in alpha beta quit; do echo "picked $c"; [ "$c" = quit ] && break; done' Enter
timeout 10 tmux send-keys -t uiux '2' Enter
for i in $(seq 1 25); do timeout 5 tmux capture-pane -t uiux -p | grep -q 'picked beta' && break; sleep 0.2; done
mkdir -p "$(git rev-parse --show-toplevel)/.dforge/ui-ux/demo"
timeout 10 tmux capture-pane -t uiux -p -e > "$(git rev-parse --show-toplevel)/.dforge/ui-ux/demo/terminal-80.ansi"
timeout 10 tmux resize-window -t uiux -x 120 -y 40
timeout 10 tmux capture-pane -t uiux -p -e > "$(git rev-parse --show-toplevel)/.dforge/ui-ux/demo/terminal-120.ansi"
timeout 10 tmux kill-session -t uiux
grep -c 'picked beta' "$(git rev-parse --show-toplevel)/.dforge/ui-ux/demo/terminal-80.ansi"   # expect 1
```

When every command succeeded and the grep printed 1, replace the `**Status:**` line of `plugins/dforge/skills/ui-ux/references/platforms/terminal.md` with `**Status:** verified 2026-10-24 on Linux with tmux $(tmux -V | cut -d' ' -f2): launch, send-keys, capture at 80 and 120 columns, kill.` (the version written out). When any step failed, keep `unverified` and record the failure in the note.

- [ ] **Step 4: Write the demo note**

Create `docs/dforge/notes/2026-10-24-ui-ux-demos.md`:

```markdown
# ui-ux demos

Run 2026-10-24 in the execution worktree.

## A20 — web walkthrough from an implementer subagent

- Page: `plugins/dforge/tests/fixtures/ui-ux/walkthrough.html` (<file:// or http.server>)
- Keyboard walk at 375x812: <result>; at 1440x900: <result>
- Error state: <result>
- Screenshots: <the four paths>

## A17 — terminal guide

- tmux <version>: <result per step>

## Left for the owner

- A2 (a fresh session loads dforge:ui-ux when brainstorming a settings screen) and A3 (a UI bug fix states the touch depth line and writes a judged proof): need a fresh interactive session.
- A17, Windows half: run `plugins/dforge/skills/ui-ux/references/platforms/windows.md` on a Windows host and update its Status line.
```

Fill every `<…>` from Steps 2-3.

- [ ] **Step 5: Clean up and commit**

```bash
rm -rf "$(git rev-parse --show-toplevel)/.dforge/ui-ux/demo"
ps -eo pid,cmd | grep -E 'http.server 8765|tmux.*uiux|chrom' | grep -v grep   # expect nothing you started
git add plugins/dforge/tests/fixtures/ui-ux/walkthrough.html docs/dforge/notes/2026-10-24-ui-ux-demos.md plugins/dforge/skills/ui-ux/references/platforms/terminal.md
git commit -m "docs(dforge): record the ui-ux walkthrough demos"
```

---

### Task 19: Validate the repository and pressure-test the skill

**Files:**
- Modify: `docs/dforge/notes/2026-10-24-ui-ux-demos.md`

**Interfaces:**
- Consumes: everything above
- Produces: the validation and pressure-run evidence (spec §Testing)

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Run the repository validation**

From the repository root:

```bash
timeout 120 node scripts/validate-repository.mjs
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 3600 node scripts/test-all.mjs
timeout 120 /root/.local/bin/claude plugin validate .
for p in dforge dr-status darkraise-ui darkraise-win32ui; do timeout 120 /root/.local/bin/claude plugin validate plugins/$p || echo "FAILED $p"; done
env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 /root/.local/bin/claude plugin test plugins/dforge
```

Expected: every command exits 0 and no `FAILED` line. A failing suite this plan touched is fixed in the task's file it names, by the rule it broke; a failure in a suite this plan never touched is reported with its output, not worked around. Confirm with `ps` that no test process is left.

- [ ] **Step 2: Pressure-run the skill (dforge:writing-skills baseline)**

Dispatch two `general-purpose` subagents in one message, each told to edit and commit nothing and to answer in under 400 words:

- **Without the skill:** "Here is an approved mockup: `<WT>/plugins/dforge/tests/fixtures/ui-ux/walkthrough.html`. You will implement it as a production React component in an existing app. List exactly what you will build and how you will verify it is done."
- **With the skill:** the same prompt, prefixed with "First read `<WT>/plugins/dforge/skills/ui-ux/SKILL.md` and its references, and follow them."

Pass: the with-skill answer states a `**UI/UX depth:**` line, lists contract items with `UI-`/`UX-`/`OP-` IDs that cover keyboard focus, the error state and Escape, and names `ui-proof check` as its done condition. Record both answers' gaps in the note: what the without-skill answer dropped, and anything the with-skill answer still missed. A with-skill answer that misses one of the pass points is a finding against `skills/ui-ux/SKILL.md`: fix the skill text that let it through, rerun only the with-skill subagent, and record both runs.

- [ ] **Step 3: Record and commit**

Append to `docs/dforge/notes/2026-10-24-ui-ux-demos.md`:

```markdown
## Validation

- validate-repository, test-all, plugin validate (marketplace and four plugins), plugin test: <result of each>

## Pressure run

- Without the skill, dropped: <list>
- With the skill: <pass points met, and anything still missed>
```

```bash
git add docs/dforge/notes/2026-10-24-ui-ux-demos.md plugins/dforge/skills/ui-ux/SKILL.md
git commit -m "docs(dforge): record ui-ux validation and pressure run"
```
