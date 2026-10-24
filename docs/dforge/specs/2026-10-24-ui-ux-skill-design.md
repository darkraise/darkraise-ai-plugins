# dforge:ui-ux — design

**Execution strategy:** sequential — the skill, its scripts, the hook wiring
and the edits to four existing skills form one chain: the hooks and gates call
the scripts, and the skill edits cite both.

## Decisions

- **Scope of the request** — "a new skill for dforge, that will auto involve
  when brainstorm items that have UI/UX/design part, or when fixing bug that
  need UI change, or anything that related to UI/UX/design, user facing stuff,
  user behavior and functionalities."
- **Approach** — the proposal presented in chat on 2026-10-24 weighed three
  candidates:
  1. the do-less option: a `ui-ux` review lens plus a checklist reference, no
     new skill. It catches defects in the diff but never puts the mockup's
     intent in front of the implementer or looks at the running UI;
  2. adopting an external skill, impeccable: the only surveyed skill that
     checks fidelity, but visually only, and tied to its own binary and
     image tooling;
  3. a dforge skill that writes a contract, carries it into every UI task and
     proves it in the running UI.

  The owner adjusted the third and did not ask for the others.
- **Name** — "ui-ux".
- **What the contract covers** — "This is not only User experience, but also
  user inteface and final output promise." The contract is therefore the
  UI/UX contract with three parts: UI, UX and Output promise.
- **Where the contract lives** — asked at the spec review: "Spec section
  (Recommended)".
- **Gate strength** — "block it": a UI change without a fresh proof report
  cannot pass the final review or be finished.
- **Platforms** — "Yes, support other platform, except MacOS, I do not have
  Mac device to verify." macOS and iOS are out of scope.
- **Hook** — "We need hook".
- **State-board mockups** — "recommend it, user will answer that": the skill
  recommends them and asks the user each time.
- **Execution strategy** — not asked (`autoRun=on`); sequential, for the reason
  above.
- **Platforms run before shipping (A17)** — asked at the spec review:
  "Window + TUI". The owner runs the windows and terminal guides once; the
  linux-desktop and android guides ship marked unverified.
- **Approval** — "Approve, run unattended".

Finish: merge

## Problem

An agent's mockup looks finished, but the build copies its layout and drops
the rest: interaction states, flows, validation and feedback, copy, responsive
behaviour, accessibility, motion and non-functional requirements. In dforge
the causes are structural:

1. A mockup shows one state of one path; what is not drawn is not built.
2. An implementer sees only its own task plus the plan's Global Constraints and
   Contracts (`plugins/dforge/skills/writing-plans/SKILL.md:310`), so the
   mockup and its intent reach it only if the plan writer restated them.
3. Nothing checks the rendered UI: visual and interactive outcomes are tagged
   `demo`, "only a person watching the result can" check them
   (`plugins/dforge/skills/brainstorming/SKILL.md:440`); acceptance QA tests
   "only through the public surface"
   (`plugins/dforge/reference/acceptance-qa.md:48`); no review lens covers UI.
4. The mockup is often built in a different technology from the product, and
   the translation loses detail.

A survey of 28 popular UI/UX skills, rules and builder prompts (2026-10-24)
found none that turns an approved design into a behavioural checklist and then
checks the running UI against it item by item. The techniques this design
borrows, and from where:

- written state, interaction and accessibility tables before code —
  Anthropic `design-handoff`;
- an uncited deviation from the approved design is a defect; a fresh-context
  reviewer — `impeccable`;
- pinned state matrices and a deviation report — the shadcn skill;
- live-environment-first review at three viewports — OneRedOak `design-review`;
- measured evidence kept apart from guesses, re-run after fixing — Addy
  Osmani `web-quality-skills`;
- "not achieved until proven otherwise" — wshobson `ui-visual-validator`;
- a realistic worst-case dataset — Emil Kowalski `break-ui`;
- checkable interaction rules (focus the first error, URL holds state,
  loading-flicker timing) — Vercel web interface guidelines;
- a saved project design memory read before each build — `impeccable`,
  `interface-design`, `ui-ux-pro-max`;
- an edit-time detector hook — `impeccable`.

## Design

### The skill

`plugins/dforge/skills/ui-ux/SKILL.md`, about 200 lines, with its depth in
`references/`. Description:

> Use when work touches anything a user sees or does - designing, building or
> changing screens, components, flows, forms, copy, styling, layout,
> interaction, accessibility or responsive behaviour, turning a mockup or
> design into code, or fixing a bug whose fix changes the UI - writes a UI/UX
> contract, carries it into every UI task, and proves it in the running UI
> before the work counts as done.

It owns the process. Aesthetic direction stays with `frontend-design` and kit
rules with `darkraise-ui` (or the project's own design system); the skill
calls on them for those parts and duplicates neither.

### Depth

The skill picks one depth and states it in one line,
`**UI/UX depth:** <touch|feature|product> — <why>`, the same format wherever
the line appears (the contract's first line, a touch report's `## Delta`):

- **touch** — a bug fix, a copy or styling change, one surface: a UI/UX delta
  of 5 to 15 items (the states, viewports, themes and neighbouring surfaces
  the change affects), written as a `## Delta` section at the top of the proof
  report with `UI-`, `UX-` and `OP-<n>` IDs like a contract, and a proof of
  that surface only, reviewed by the touch-depth judge against the delta. No
  spec section.
- **feature** — a new or changed flow or screen: the contract as a spec
  section, a full walkthrough of every flow it touches, and the feature-depth
  judge.
- **product** — a new product or surface family: the feature depth plus the
  project UI profile's design decisions, written or extended.

### The project UI profile

`<docs>/ui-ux/profile.md`, created on first use with the user's answers and
read before every UI task. It holds:

- **Platform** and **Harness** — how to launch the UI and drive it (see
  Platforms);
- **UI paths** — the globs that count as UI files. One resolver,
  `scripts/ui-proof paths`, prints the effective globs for every consumer (the
  hooks, the gate, plan-lint and lens-route): the profile's globs, or with no
  profile the union of the platform defaults, which are
  - web: `*.tsx *.jsx *.vue *.svelte *.astro *.html *.css *.scss *.sass *.less`;
  - windows: `*.xaml *.axaml *.rc *.Designer.cs *.razor *.cshtml`;
  - android: `res/layout/*.xml res/values/*.xml res/drawable/*.xml`;
  - linux-desktop: `*.ui *.qml *.glade *.blp`;
  - terminal: none, the profile must name them;

  each excluding `*.test.*`, `*.spec.*` and `*.stories.*`. Never a bare `*.ts`,
  `*.cs` or `*.kt`: a project whose UI lives there names it in its profile;
- **Design system** — where tokens and components come from (for example
  `theme.config.ts` and darkraise-ui), and the paths that define tokens;
- **Viewports** and **Themes** to prove at;
- **Users and voice** — who uses the product, and its copy rules;
- **Decisions** — dated design decisions with their reasons, appended as they
  are made;
- **Screenshots** — `local` (default) or `commit`.

The skill creates the profile the first time it runs in a project, so the
profile's existence is what turns the gate on: `ui-proof check` gates a
project that has a profile, and any plan whose spec has a UI/UX contract. A
project with neither still gets the edit-time lint and the reminder (this
repository's cockpit `.tsx` files included), but no gate, no `ui-ux` lens,
and no hold unless the skill ran this session.

### The UI/UX contract

A spec section `## UI/UX contract`, always in the spec, so every consumer
reads one place; its first line is the `**UI/UX depth:**` line. Every item
carries an ID, `UI-<n>`, `UX-<n>` or `OP-<n>`, so plans, briefs, proofs and
reviews can cite it; a mockup region annotated with an ID is the same item.

- **UI** (`UI-<n>`) — the interface: the component map (every mockup region
  mapped to an existing component and its tokens, no raw values), layout and
  hierarchy, typography, imagery, iconography, the theme variants, and the
  mockup's state boards with their paths.
- **UX** (`UX-<n>`) — the experience: users and their jobs; flows with entry
  points, other paths, cancel, undo, back and deep links; the state matrix
  per surface (data states: loading, empty first use, empty after filtering,
  partial, error, offline, denied, worst-case content; control states:
  default, hover, keyboard focus, active, disabled, pending, selected,
  invalid); interactions and feedback, including where focus goes after an
  action; forms and validation; the copy deck; responsive changes per
  breakpoint; motion and its reduced-motion fallback; accessibility (focus
  order, accessible names, announcements, contrast); non-functional
  requirements with numbers (performance budgets, data volumes, i18n and
  right-to-left, supported platforms).
- **Output promise** (`OP-<n>`) — what the shipped result guarantees as a
  whole: which state boards are binding and how closely (components, tokens,
  hierarchy and copy must match; pixel offsets need not), the viewports,
  themes and platforms it is proven on, the accessibility level, the budgets,
  every declared deviation from the mockup with its reason, and what is out
  of scope.

Each contract item becomes one or more acceptance statements whose text starts
with its ID, for example `A12. [test, high] UX-4: Escape closes the dialog and
returns focus to its trigger.` A behaviour statement is tagged `test` only when
the profile's Harness names a UI test runner the project can run (for example
its Playwright suite); otherwise it is `demo`. Every statement that starts with
a contract ID, `test` or `demo`, is also proven by its row in the proof report.
`reference/acceptance-qa.md` gains one rule: a `test` statement that starts
with a contract ID is written for the profile's UI test runner, so Acceptance
QA never meets a UI statement it has no surface for.

### Shape (design phase)

Run from brainstorming when the design has a user-facing part, before the
acceptance statements are drafted, and from systematic-debugging's Phase 4
when the fix changes the UI (touch depth). Under `autoRun=on`, where
brainstorming asks nothing after its clarifying questions, the profile
questions and the state-board question are asked among those clarifying
questions and quoted in the spec's `## Decisions`; the contract is then written
with the spec.

1. Read the profile, or create it.
2. Write the contract (feature, product) or the delta (touch), working from
   `references/contract-template.md`, `references/state-catalogue.md` and
   `references/interaction-rules.md`.
3. Ask the user whether to build state boards: every state of each screen
   side by side, annotated with contract IDs, built from the project's real
   components where the platform allows. Ask at every depth: recommend yes at
   feature and product depth and no at touch depth; the user decides.
4. Define the worst-case dataset the proof will use: the longest names, the
   largest counts, empty and missing values, right-to-left text.

### Carry (plan and execution)

- **writing-plans** — every task whose Files match the profile's UI paths
  carries a `**UI/UX:**` line naming the contract IDs it delivers, and every
  `UI-` and `UX-` ID is named by at least one task (`OP-` IDs describe the
  whole result and need a proof row, not a task). `scripts/plan-lint` fails a plan
  that breaks either rule when its spec has a UI/UX contract.
- **task-brief** — for a task with a `**UI/UX:**` line, the brief appends the
  cited contract items verbatim from the spec and the
  paths of the state boards they cite.
- **The implementer** — renders its work through the profile's harness before
  reporting, and its report maps each cited ID to evidence (a screenshot path,
  a test name, or a reason it cannot be shown yet).

### Prove (verification)

`references/walkthrough.md`, run by the session or an implementer seat (judge
seats have no browser tools):

1. Launch through the harness; seed the worst-case dataset.
2. Walk every flow in scope by pointer and by keyboard alone, at every
   profile viewport and theme.
3. Force each state in the matrix (on the web: route the network to slow,
   failing, empty and huge responses).
4. Run the automated checks the platform offers: an axe scan on the web,
   console errors, horizontal overflow, contrast.
5. Capture a screenshot per item and state, beside the state board it
   promises.
6. Write the proof report and stamp it with `scripts/ui-proof stamp`.

The proof report, `<docs>/ui-ux/proofs/<date>-<slug>.md` (the spec's slug, or
at touch depth the branch or bug), holds a header and one row per contract ID
(at touch depth, one row per ID in its `## Delta`):

- **Header:** `**Contract:** <spec path>` or `**Contract:** touch`, the
  platform, viewports and themes, `**Evidence:** local|committed`, and the UI
  fingerprint `ui-proof stamp` wrote.
- **Rows:** `pass`, `deviation` (citing the user's answer, profile decision or
  accessibility need that forced it), `fail`, or `unverifiable` (with the
  reason). An uncited deviation is a `fail`. Every `pass` and `deviation` row
  cites at least one screenshot or test name.

Screenshots go to `.dforge/ui-ux/<slug>/` in the checkout (created through
`dforge_state_ignore` in `scripts/lib/dforge-dir.sh`, so git ignores it, and
inside the root Playwright MCP allows writes to), or beside the report when the
profile says `commit`. Local evidence goes when the worktree is removed; the
report's verdict rows are what remains, and `**Evidence:** local` says so. The
walkthrough closes the browser and every process it started, and removes the
`.playwright-mcp/` files it created.

A judge then reviews the report with `criteria/ui-ux-proof.md`:
`dforge:judge-opus` at feature and product depth, `dforge:judge-sonnet-high`
at touch depth, and on a Codex host the native judge seat
`reference/native-codex.md` names for that rank. It reads the contract, the
screenshots and the state boards, assumes each item is unproven until a
screenshot or test shows it, and returns `ship` or `fix` with the IDs it
disputes, ending its reply with `Verdict: ship|fix <fingerprint>`. Judge
seats are read-only, so the session saves the reply verbatim to
`<docs>/ui-ux/proofs/<date>-<slug>.judge.md`, as lens replies are saved to
`<workspace>/lens-<id>.md`, and records `**Judge:** ship|fix <fingerprint> —
<judge file>` in the report. `ui-proof stamp` removes any judge line whose
fingerprint differs from the new stamp, so an edit after the verdict needs a
new verdict.

**The fingerprint** is a hash over every file matching `ui-proof paths`,
tracked and untracked but not ignored, by working-tree content (`git ls-files
-co --exclude-standard` filtered by the globs, then `git hash-object
--stdin-paths`). It does not depend on any base, so the Stop hook and the final
review compute the same value, and git does the hashing, which keeps the Stop
hook inside its 60 seconds.

### The gate (blocking)

`scripts/ui-proof check --base <ref> [--spec <path>]` — `--base` is
required, so committing the work can never hide it.

1. **Scope.** When no file matching `ui-proof paths` differs between `<ref>`
   and the working tree (committed or not), exit 0.
2. **Which report.** With `--spec` naming a spec that has a `## UI/UX
   contract`, the report is the one whose `**Contract:**` names that spec and
   whose fingerprint is current, and the depth comes from the spec's
   `**UI/UX depth:**` line, never from the report. Otherwise it is a report
   whose fingerprint is current. No such report: exit 1, naming the newest
   report found.
3. **Coverage.** Whenever the chosen report's `**Contract:**` names a spec,
   with or without `--spec`, every contract ID of that spec has a row; a touch
   report needs a row per ID in its `## Delta`. A missing ID fails.
4. **Freshness.** The report's fingerprint equals the fingerprint of the
   current UI files; the fingerprint covers their contents, committed or not.
5. **Verdicts.** No `fail` row; every `pass` and `deviation` row cites
   evidence, and every cited screenshot exists while `**Evidence:** local`;
   every `unverifiable` row carries an `**Accepted by:**` line; the judge line
   reads `ship` with the current fingerprint, and the judge file it cites
   exists and ends with the same verdict line.

Exit 1 names each failed step and the files or IDs behind it.

It blocks in three places, each passing its own base:

- the final review runs `ui-proof check --base MERGE_BASE --spec <the plan's
  Spec>` after the gates; exit 1 stops the review, like a red gate. The fix
  wave edits UI files and so stales the report: the check runs again after the
  wave, and exit 1 then means Prove again (auto run) or stop (attended);
- finishing-a-development-branch runs the same command after Step 1 and
  before Step 4's recorded-choice block. Exit 1 (in an auto run, exit 1 from
  the check after its Prove re-run) turns a recorded `merge` or `pr` into
  `keep`, and otherwise presents only "prove it first" or "keep the
  branch", ending with `Which option?` so `turn-end.sh` recognises the menu;
- verification-before-completion gains the claim row "the UI works", which
  requires a passing `ui-proof check --base <the branch's base, as finishing
  Step 3 determines it>`, plus `--spec` when the work has one.

**In an auto run** nobody can answer a question, but the Prove phase needs
none: on exit 1 the run performs the Prove phase itself and checks again. Only
an `unverifiable` row, which needs the user's words, stops it:
`scripts/auto-run stop --reason "ui proof needs the user"`, and finishing then
keeps the branch.

An `unverifiable` row (a platform with no harness on this host, or macOS)
passes only with `**Accepted by:** <the user's words, quoted>`; the skill
forbids writing that line without the user saying so in the conversation.

### Hooks (Claude Code)

- **PostToolUse on Edit, Write and MultiEdit**, `scripts/ui-edit-hook.sh`,
  timeout 30 seconds: when the edited file matches `ui-proof paths`, run
  `scripts/ui-lint` on that file and return its findings, each naming the rule
  and line, in `hookSpecificOutput.additionalContext` (it never blocks), and,
  on the first UI edit of a session whose transcript shows no `dforge:ui-ux`
  run, add one line there saying the skill applies.
- **Stop**, a separate hook script `scripts/ui-turn-end.sh` beside
  `turn-end.sh`, timeout 60 seconds, so the plan-ledger hold stays untouched.
  It holds the stop once when all of these are true:
  - the project has a profile, or the session's transcript shows a
    `dforge:ui-ux` run;
  - `ui-proof check --base <the turn's start head>` exits 1. That head is the
    commit on the `.refs` line (written by `turn-start.sh`) whose worktree is
    this checkout, so a turn that committed its UI edit is still caught; no
    stamp, a detached HEAD or no such line means exit 0;
  - no auto run is bound to the session (`auto-run pending` exits nonzero;
    a bound run prints `none`, never an empty line), so it never contends with
    `turn-end.sh`'s auto-run hold;
  - the last assistant message does not carry `UI proof: pending — <why>`,
    the honest alternative the reason offers.

  The hold's reason and `systemMessage` name the stale files or missing IDs.
  Its retry (`stop_hook_active`) passes, as the existing hold does. UI edits
  left unproven are held once per turn until they are proven or the pending
  line is given.

`scripts/ui-lint` holds only high-precision rules, each with a passing and a
failing fixture in its test: on the web, raw colour values outside token
files, an outline removed with no focus-visible replacement, a click handler
on a non-interactive element with no role or key handler, an image without
`alt`, `transition: all`, disabled zoom, a positive `tabIndex`, a blocked
paste; in XAML, hard-coded brushes instead of theme resources; in Android
layouts, hard-coded colours and text, and images without a content
description. The plan fixes the exact list.

On Codex, which runs no hooks, the skill tells the agent to run
`scripts/ui-lint` after UI edits and `scripts/ui-proof check` before claiming
done; the final-review and finishing gates are scripts and apply unchanged.
Whether a Codex native implementer can drive a browser is unverified; the
Codex walkthrough ships marked unverified, like the harnesses under A17.

### Platforms

`references/platforms/` holds one harness guide per platform:

- **web** — Playwright MCP or the project's Playwright runner (Electron through
  Playwright's Electron support);
- **windows** — UI Automation through FlaUI or pywinauto, or the project's own
  harness (for example darkfoto's GuiVerify); runs only on a Windows host;
- **linux-desktop** — GTK, Qt and Tauri under Xvfb, driven by xdotool, with
  the AT-SPI tree for accessibility;
- **android** — an emulator through adb (`screencap`, `input`, `uiautomator
  dump`);
- **terminal** — tmux `send-keys` and `capture-pane` at two widths.

macOS and iOS are not supported; a proof on them is `unverifiable`.

### Integration edits

- `using-dforge` — a routing row: anything a user sees or does goes to
  `dforge:ui-ux`, alongside brainstorming or systematic-debugging.
- `brainstorming` — run the skill's Shape phase before drafting acceptance when
  the design has a user-facing part.
- `systematic-debugging` — Phase 4: a fix that changes the UI runs touch depth.
- `writing-plans` and `scripts/plan-lint` — the `**UI/UX:**` line and its
  two rules.
- `scripts/task-brief` — the appended contract items.
- `reference/delegated-task.md` — render before reporting; map IDs to
  evidence.
- `reference/final-review.md` — the `ui-proof check` step and its re-run after
  the fix wave, and a `ui-ux` lens.
- `reference/acceptance-qa.md` — contract-ID `test` statements use the
  profile's UI test runner.
- `reference/native-codex.md` — its prose lens priority order gains `ui-ux`
  second, and its "read each Applies: line by hand" instruction explains the
  `ui-paths` clause.
- `criteria/lenses/ui-ux.md` and `scripts/lens-route` — code-level defects in
  UI files. Its `Applies:` line takes a new clause, `ui-paths`, which
  lens-route resolves through `ui-proof paths`, and `lens_order` places
  `ui-ux` second, after `security`, so the default cap of four keeps it on a
  typical `.tsx` branch. The `ui-paths` clause matches only when the project
  has a profile or the plan's spec has a UI/UX contract.
- `skills/finishing-a-development-branch` and
  `skills/verification-before-completion` — the gate.
- `hooks/hooks.json` — the PostToolUse entry, the Stop check, and its
  `description` string.
- The plugin README and the dforge description in `plugin.json`.

### Out of scope

An aesthetic database or taste bans (frontend-design and the design system own
those), image generation, pixel-diff tooling (mockups built in another
technology make pixel diffs brittle; the judge compares side by side), macOS
and iOS, and an edit hook that blocks.

## Acceptance

A1. [test, high] The skill exists at `plugins/dforge/skills/ui-ux/SKILL.md` with `name: ui-ux`, and `claude plugin validate` passes on dforge with it.
A2. [demo, high] Asked to brainstorm a feature with a settings screen, a fresh Claude Code session with dforge loads `dforge:ui-ux` without being told to, shown by one recorded session run.
A3. [demo, high] Asked to fix a bug whose fix edits a `.tsx` file, the session states a `**UI/UX depth:** touch — <why>` line and writes a judged proof report before saying the bug is fixed.
A4. [test, high] `scripts/plan-lint` fails a plan whose spec has a UI/UX contract when a task touching a UI path has no `**UI/UX:**` line, or when a `UI-` or `UX-` ID is named by no task, passes it when only an `OP-` ID is named by no task, and passes the same plan once both rules hold.
A5. [test, high] `scripts/task-brief` appends the cited contract items verbatim to the brief of a task with a `**UI/UX:**` line, and appends nothing to a task without one.
A6. [test, high] `scripts/ui-proof check --base <ref>` exits 0 when no UI file differs from `<ref>`, and when the bound report covers every contract ID, its fingerprint is current, it has no `fail` row, every row cites evidence that exists, and its judge line reads `ship` with the current fingerprint.
A7. [test, neg, high] `scripts/ui-proof check` exits 1 when UI files changed after `<ref>` and no report matches, whether the change is committed or not, and when a UI file changed after the report was stamped.
A8. [test, neg, high] `scripts/ui-proof check` exits 1 when the report has a `fail` row, an uncited `deviation`, a row with no evidence or a missing cited screenshot, an `unverifiable` row without an `**Accepted by:**` line, a contract ID with no row, or a judge line that is not `ship` or carries another fingerprint.
A9. [test, neg, high] With `--spec` naming a spec that has a UI/UX contract, `scripts/ui-proof check` refuses a touch report or a report bound to another spec, even when its fingerprint is current.
A10. [test, high] `scripts/ui-proof stamp` removes a judge line whose fingerprint differs from the new stamp.
A11. [test, high] `scripts/ui-proof paths` prints the profile's globs, and with no profile the union of every platform's defaults; the hooks, the gate, plan-lint and lens-route all take their globs from it.
A12. [test, high] The PostToolUse hook returns lint findings, each naming its rule and line, in `hookSpecificOutput.additionalContext` for an edited UI file, returns nothing for a non-UI file, and never blocks the edit.
A13. [test, high] On the first UI edit of a session whose transcript shows no `dforge:ui-ux` run, the hook's context names the skill; on later edits it does not repeat it.
A14. [test, neg, high] The Stop check holds once, naming the stale files or missing IDs, a turn that edited and committed UI files without a passing proof in a project with a profile, and passes its retry (`stop_hook_active`).
A15. [test, neg, high] The Stop check never holds in a project with no profile whose session has not run the skill, nor while an auto run is bound to the session, nor when the last message carries `UI proof: pending — <why>`.
A16. [test, high] Each `scripts/ui-lint` rule reports its failing fixture and stays silent on its passing fixture.
A17. [demo, confirmed] The windows and terminal harness guides each carry a procedure that a session on that platform ran once; the linux-desktop and android guides ship marked unverified.
A18. [test, neg, high] In a project with a profile, or for a plan whose spec has a UI/UX contract, `scripts/lens-route --final` routes the `ui-ux` lens when the diff touches a UI file, also when security, lang-typescript, test-quality and silent-failures all match under the default cap of four; it does not route it when no UI file changed, nor when a `.tsx` file changed in a project with no profile whose plan's spec has no contract.
A19. [test, high] The final review and finishing skills each name `ui-proof check --base MERGE_BASE --spec` and say that exit 1 stops them, and the final review names the auto-run path: prove, check again, stop only for an `unverifiable` row.
A20. [demo, high] A web walkthrough driven by Playwright MCP from an implementer subagent, run in a worktree against a fixture page under `plugins/dforge/tests/fixtures/`, produces screenshots under `.dforge/ui-ux/` at the profile viewports and a keyboard-only pass.
A21. [test, high] `reference/acceptance-qa.md` states that a `test` statement starting with a contract ID is written for the profile's UI test runner, and `skills/ui-ux/SKILL.md` states that a behaviour statement is tagged `demo` when the profile names no UI test runner.
A22. [test, neg, high] `scripts/ui-proof check` exits 1 when the judge line cites a judge file that is missing or whose verdict line differs, and after a fix wave edits a UI file that the report's fingerprint covered.

## Critic findings

Architecture critic (`dforge:judge-opus`), 2026-10-24: 2 Blocker, 4 High, 6
Medium, 2 Nit, all fixed in the spec.

- Blocker — the gate passed once the work was committed: `--base` is now
  required and each call site passes its own (The gate; Hooks). A7, A14.
- Blocker — any fresh report satisfied the gate: the report is bound to the
  spec, the depth comes from the spec and every contract ID needs a row
  (The gate). A8, A9.
- High — the judge verdict was not tied to what it saw: the judge line
  carries the reviewed fingerprint and a new stamp removes a stale one
  (Prove). A10.
- High — the lens cap would drop the `ui-ux` lens: it is ordered second
  (Integration edits). A18.
- High — auto runs had no path through the gate: the run proves and checks
  again, and stops only for an `unverifiable` row; the Stop check stands down
  while an auto run is pending (The gate; Hooks). A15, A19.
- High — two sources of truth for UI files: one resolver, `ui-proof paths`,
  feeds every consumer (The project UI profile). A11.
- Medium — local evidence vanishes with the worktree: the report says
  `**Evidence:** local` and the check verifies cited screenshots exist while
  it can (Prove).
- Medium — reports could overwrite each other: dated names, bound by
  `**Contract:**` or fingerprint rather than modification time (Prove).
- Medium — two homes for the contract: always the spec section
  (The UI/UX contract).
- Medium — "the session ran the skill" was undefined for scripts: the gate
  depends on the profile or the spec's contract; only the hooks read the
  transcript (The project UI profile; Hooks).
- Medium — touch proofs were self-certified: every row cites evidence and a
  `judge-sonnet-high` seat reviews touch proofs (Depth; Prove).
- Medium — the Codex path was uncovered: the Codex judge seat is named and the
  Codex walkthrough ships marked unverified (Prove; Hooks).
- Nit — hook cost and failure output: timeouts of 30 and 60 seconds, and
  holds name their files or IDs (Hooks).
- Nit — PostToolUse output channel: `hookSpecificOutput.additionalContext`
  (Hooks). A12.

## Riskiest assumption

That the walkthrough can run where the work happens: an implementer subagent
must be able to drive the browser through Playwright MCP, take screenshots and
read the accessibility tree, and a judge seat must be able to read the saved
screenshots. Evidence, probe run on 2026-10-24: a `dforge:impl-sonnet-low`
subagent loaded the deferred `mcp__playwright__*` tools with ToolSearch,
navigated, resized to 375x700, pressed Tab twice (the snapshot marked the
second button `[active]`), took a screenshot and closed the browser; the
session's Read tool displayed the screenshot. One constraint surfaced:
Playwright MCP refused a screenshot path outside
`/root/repositories/darkraise-ai-plugins` and its `.playwright-mcp/` directory
("outside allowed roots"), and wrote its page snapshots to `.playwright-mcp/`
unasked. Hence screenshots live in the checkout (see Prove), and the
walkthrough removes the `.playwright-mcp/` files it created. The non-web
harnesses are unverified — the plan's platform tasks verify each one (A17).
The probe also ran in the primary checkout, while auto runs execute in a
worktree under `.worktrees/`; whether Playwright MCP's allowed root admits
that worktree's `.dforge/ui-ux/` is unverified — the plan's first task
verifies it (A20).

## Testing

Shell tests in `plugins/dforge/tests/` beside the existing ones: `ui-proof`,
`ui-lint` with per-rule fixtures, the PostToolUse hook and the Stop check
(following `hook.test.sh`), and new cases in `plan-lint.test.sh`,
`lens-route.test.sh` and the task-brief tests. The skill text follows
dforge:writing-skills: a baseline run without the skill on a mockup-to-code
task records what gets dropped, and the same run with it must deliver the
contract, the proof and the gate. The repository's validation applies:
`node scripts/validate-repository.mjs`, the maintained suites, `claude plugin
validate` and `claude plugin test plugins/dforge`.

## Review rulings

Fable spec review, round 1 (2026-10-24), applied:

- Contract home: the spec section, kept pending the owner's answer.
- iOS excluded with macOS: kept; proving iOS needs a Mac.
- Finishing may keep a branch without proof: kept; keeping integrates nothing.
- State boards: asked at every depth, recommended at feature and product.
- The edit hook never blocks: kept; "block it" answered gate strength.
- Judge seats: judge-opus at feature and product, judge-sonnet-high at touch.
- Screenshots: `.dforge/` created through `dforge_state_ignore`.
- Behaviour is `test` only with a UI test runner, else `demo`.
- Fingerprint: every UI-path file by working-tree content, independent of base.
- Several reports for one spec: the one with the current fingerprint.
- Task coverage: `UI-` and `UX-` IDs only; `OP-` IDs need a proof row.
- Touch delta: a `## Delta` section in the proof report, with IDs.
- Stop check: stands down while an auto run is bound (`auto-run pending` exits 0).
- verification-before-completion base: the branch's base from finishing Step 3.
- Finishing gate: after Step 1, before the recorded-choice block; exit 1 makes `merge` or `pr` into `keep`.
- A2: settled as one recorded session run; `claude plugin eval` is not run anywhere in the repository.
- A17: an unrun guide ships marked unverified; which platforms to run goes to the owner.
- A20: settled as a fixture page under `plugins/dforge/tests/fixtures/`, run in a worktree.
- Defects fixed: autoRun=on question slot (Shape), coverage applied without `--spec` (The gate), gate re-run after the fix wave, judge reply saved and cited, native-codex.md lens order and hooks.json description, default globs listed and the `ui-paths` lens clause limited, worktree case added to the riskiest assumption, one depth-line format.

Fable spec review, round 2 (2026-10-24): every round-1 defect confirmed fixed
except the proposal citation, now inlined in `## Decisions`; its new findings
(A4 and A18 aligned with the design, A21 made checkable, the auto-run finishing
order, the A3 depth line, the hold condition in the profile section) are fixed.
