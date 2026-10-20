# Gotchas

Traps a session meets in this repository, each led by the symptom that shows it is inside one.

## Shell scripts and their tests

### A pipeline's caller fails with status 141 (or a `pipefail` status) after an `awk … exit`
Cause: an `awk` that calls `exit` stops reading; the upstream writer takes SIGPIPE, and under `set -o pipefail` that becomes the pipeline's status. `scripts/lib/plan.sh` documents the hazard, and `task-brief` runs `set -euo pipefail`
Workaround: set a `found` flag and print in `END`, never `exit` early
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### A diagnostic after `x=$(jq … | tr …) || return 1` never prints
Cause: under `set -uo pipefail` the `|| return 1` fires on jq's failure before the line that prints the diagnostic
Workaround: capture the status in a variable (`rc`) and test it separately, then print
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### A test that writes `Alpha.json` next to `alpha.json` loses one of them on Windows
Cause: NTFS is case-insensitive, so the second write overwrites the first
Workaround: put a case-sensitivity fixture in its own temporary directory
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### A command added to a script prints nothing under `tests/detect.test.sh`
Cause: that suite seals `PATH` to shims for a fixed list (`jq timeout head tr node bash dirname cygpath` as of 2026-09-21); any other command (`basename`, `sort`, `grep`) is missing, and the script's output silently vanishes
Workaround: add the command to the suite's shim loop, or avoid it (`${file##*/}` instead of `basename`)
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### `VAR=x some_function` behaves differently across bash versions
Cause: whether a temporary assignment before a function call reaches the function's children, and whether it persists afterwards, changed in bash 5.x
Workaround: pass the mode as an argument, or `export` and `unset` explicitly
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### A suite using `$TMP` aborts under `set -u`
Cause: each suite names its own temporary directory variable (`tests/inline-mode.test.sh` uses `DTMP`); an appended test that assumes `$TMP` hits an unset variable
Workaround: read the suite's own setup before appending a test
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-executor-interface-plan-review.md@7221a67

### `tests/plan-lint.test.sh` dies with no failure line
Cause: it takes about 4m20s on this machine (2026-09-20), so a 120 s or 200 s bound kills it silently
Workaround: bound it at 600 s or more
Verified: 2026-09-20
Source: docs/superpowers/notes/2026-09-20-dr-superpowers-item-registers-followups.md@382b264

### `tests/budget-line.test.sh` fails three assertions on this machine
Cause: the suite hardcoded a 465k window, while this machine's `autoCompactWindow` of 650000 gives 790k; it failed identically at the commit before the item-registers plan
Workaround: none recorded; the three failures come from the machine's settings, not the change under test
Verified: 2026-09-20
Source: docs/superpowers/notes/2026-09-20-dr-superpowers-item-registers-followups.md@382b264

### `bash: rg: command not found`, or `tests/ui-discovery.test.mjs` fails
Cause: `rg` is only a shell function on this machine, not an executable on `PATH`; the test passes where an `rg` executable exists
Workaround: use `grep` in scripts and plan steps
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-09-21-dr-superpowers-revising-plans-followups.md@da5b2e3, docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### A cached helper in `lib/roots.sh` re-reads its config on every call
Cause: roots.sh loads lazily and caches in shell variables; a `$(…)` subshell loses the cache, and a ConfigError there exits only the subshell's script
Workaround: call `forge_stores_init` (now `dforge_stores_init`) in the main shell before calling the helpers repeatedly
Verified: 2026-10-13
Source: docs/superpowers/notes/2026-10-13-darkmem-store-options-plan1-inventory.md@3a2bdd5

## Plans and skills

### `plan-lint`, `review-route`, `task-brief` and `plan-revise` skip a plan silently
Cause: its tasks are headed `### Task A1`; `plan_tasks` recognises numeric task headings only (spec of revising-plans §4), so three darkcloud plans were invisible (register row 6 of `registers/2026-09-20-review-fixes-deferrals.md`)
Workaround: number tasks `Task 1`, `Task 2`, …
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-dr-superpowers-revising-plans-followups.md@da5b2e3

### Adding a Routing row to `using-superpowers` overflows its budget
Cause: the entry point has a 4,800-byte budget; 66 bytes were left on 2026-09-21, so the next row forces trimming another
Workaround: trim an existing row in the same change
Verified: 2026-09-21
Source: docs/superpowers/notes/2026-09-21-dr-superpowers-revising-plans-followups.md@da5b2e3

## Mods (the cockpit)

### `hooks module did not load: … is not a function declared at the top of this file`
Cause: `$` may go only to top-level functions of the same file, and a hook must be inline or top-level, never a const closure (memory `mod-hooks-need-top-level-functions`)
Workaround: share code through top-level functions taking `$`; run `claude plugin test` after each refactor
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### A mod cannot load a `.json` file
Cause: the engine's module loader refuses `.json` imports; a `.mjs` outside `hooks/` (`import SCHEMA from '../../config/schema.mjs'`) imports, validates and tests fine (probe 2026-10-11)
Workaround: keep shared data in an `.mjs` module (the dr-forge merge spec was amended to `config/schema.mjs`)
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca

### A setting registered once at load ignores later changes
Cause: options read at `register` time are fixed for the module's life; on 2026-10-11 76 uses read them there, and `if (guardAttribution) { on('attribution.text', …) }` registered a hook conditionally
Workaround: register every hook unconditionally and read the live option inside it
Verified: 2026-10-11
Source: docs/superpowers/notes/2026-10-11-dr-forge-plan-research.md@e7f93ca
