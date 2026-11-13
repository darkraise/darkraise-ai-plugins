# Reviewer-Only External Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No plan task is implemented by Codex or agy any more; both families review only, through a parallel panel of Codex `gpt-6.1-sol`/`gpt-6-astra` and agy `gemini-4-argon`/`claude-opus-5-5` chosen by risk, with an agy review switch in the cockpit.

**Architecture:** Build the agy review runner first and verify plan mode with two real runs; then strip every reader of `**Executor:**` lines, delete the lane runners and their ladder blocks, shrink the registry and both gates to the review surface, add `run-review-panel`, route reviews to it, and finally rewrite the references, skills and release surface.

**Tech Stack:** Bash scripts and bash test suites, Node (`.mjs`) helpers and config schema, TypeScript cockpit tests, Markdown references and skills.

**Spec:** docs/dforge/specs/2026-11-12-reviewer-only-externals-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest tasks total 8 and Task 9 has risk 3

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-13 — dforge:judge-opus — executability 12 / coherence 14 / coverage 15 / assumptions 12 (round 2)

## Global Constraints

- All work happens in `/root/repositories/darkraise-ai-plugins/.claude/worktrees/retire-executor-lanes` on `feat/retire-executor-lanes`. Nothing touches the primary checkout `/root/repositories/darkraise-ai-plugins` (live `feat/dflow` work).
- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind. Task 3's commit is `refactor(dforge)!:` with a `BREAKING CHANGE:` body line, so `scripts/release.mjs` releases 5.0.0; no task edits a `"version"` line.
- No code comment unless the why is non-obvious; never reference this task or plan in a comment.
- Nothing is pushed before finishing.
- Do not edit historical docs (`docs/dforge/plans/*`, `docs/dforge/specs/*`, `docs/dforge/notes/*`, `docs/dforge/registers/*`) other than this plan, its spec and its register.
- Every test, suite and CLI command runs under `timeout`. Run one plugin suite as `timeout 600 bash plugins/dforge/tests/<name>.test.sh [part…]`.
- No reviewer run ever passes `--dangerously-skip-permissions`. Codex runs remain one at a time per machine.
- Real, billed agy runs happen only in Task 1 (one on `gemini-4-argon`, one on `claude-opus-5-5`); every test uses the stub agy (`plugins/dforge/tests/fixtures/stub-agy/agy`) and the stub Codex plugin.
- A new suite under `plugins/dforge/tests/` gets a `windowsSeconds` weight in `scripts/test-shards.mjs`; a deleted suite loses its weight and any `suiteSeconds`/`suiteParts` entry in `scripts/test-all.mjs`.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset) — convert the path with `cygpath -m` before the call (`dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches — normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep — pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes — pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails — import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process — create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running — run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **C1 `scripts/run-agy-review.sh`:** `--kind task|risk3|plan|final --cwd DIR --out FILE (--prompt FILE | --base SHA) [--tier light|heavy] [--dry-run]`; `--tier` applies to task kinds only (default heavy); plan and final take the heavy rows. Env seams: `AGY_REVIEW_LADDER` (default `reference/ladder.md`), `AGY_REVIEW_GATE` (default `scripts/agy-gate`), `AGY_REVIEW_GRACE` (default `60`). One status line on stdout: `agy-judge <model>/<effort> status=<OK|FALLBACK|TIMEOUT|FAILED> exit=<n> out=<path> evidence=<e>`, plus ` reason=<token>` on every non-`OK` line (C5). Exit 0 on `OK`/`FALLBACK`, 1 on `TIMEOUT`/`FAILED`, 2 on a usage error. `--out` receives the `structured_output` JSON for task and plan kinds, and the `review` string as text for `final`.
- **C2 ladder `agy-judge` block** (`reference/ladder.md`, beside `codex-judge`): rows `claude-opus-5-5 high 5400` then `gemini-4-argon high 2400`; first row preferred, last row the fallback and the light tier.
- **C3 `scripts/lib/snapshot.sh`:** `dr_state_error`, `_dr_submodule_head`, `_dr_is_gitlink`, `dr_canonical DIR`, `dr_snapshot ROOT OUT` (JSON with `.root`, `.head`, `.index`, `.files[] {path,hash,mode,kind}` covering tracked and untracked files) and `dr_task_assert_snapshot EXPECTED`, moved verbatim with their private helper from `scripts/lib/task-state.sh`.
- **C4 `criteria/agy-final-review-schema.json`:** an object schema with one required string property `review`.
- **C5 non-`OK` reason tokens** (both runners and the panel): `gate`, `refused`, `quota`, `quota-stderr`, `timeout`, `wrote`, `schema`, `error`. A `wrote` run also writes the changed paths, one per line (`HEAD` and `stash` stand for a moved head and a changed stash list), to `<out>.wrote`.
- **C6 registry entry** (`reference/executors/<id>.json`, after Task 6): `id`, `locator`, `probe{command,op}`, `gate`, `runner`, `reference`, `session_dir`, `session_dir_env`, `priority`, `surfaces: ["review"]`, `blocks{judge}`, `reasons`. `scripts/executors` requires `id`, `locator`, `probe.command`, `probe.op`, `gate`, `runner`, `session_dir`, `surfaces`; `ranked` stays (ascending priority: agy 10, codex 20).
- **C7 `scripts/detect-executors.sh [ID ...]`:** with ids, probes and prints only those registered ids; with none, every registered id. No PATH-only rows.
- **C8 gate lines:** `codex-gate usable=<b> reason=<r> review=<b> resets_at=<iso|-> source=<probe|cache|setting>`; `agy-gate usable=<b> reason=<r> review=<b> resets_at=<iso|-> claude=<on|off> claude_resets_at=<iso|-> source=<probe|cache|setting>`. `review=true` needs the setting on (`codexReview` / `agyReview`) and the policy's `trust.calibration: pass` (Codex) / `trust.review: pass` (agy). Setting off answers `usable=false reason=setting source=setting` without probing.
- **C9 `agyReview` setting** (`config/schema.mjs`, right after `codexReview`): `type: 'boolean', default: false, enforcedBy: 'script', group: 'Workflow', target: 'dforge', label: 'Agy reviews', title: 'Let Antigravity review'`, description `On lets the Antigravity CLI (agy) take review seats when its gate passes and its review surface is trusted. Off, the default, keeps agy out of every review.`
- **C10 `scripts/run-review-panel`:** `--kind task|plan|final --tier light|heavy --cwd DIR --out-dir DIR (--prompt FILE | --base SHA)`. Families in `scripts/executors ranked` order. Env seams for tests: `PANEL_CODEX_GATE`, `PANEL_AGY_GATE`, `PANEL_CODEX_RUNNER`, `PANEL_AGY_RUNNER`, `PANEL_LADDER`. Per family: out file `<out-dir>/<id>.json` (`<id>.md` for final), stderr `<out-dir>/<id>.stderr`. Prints one status line per family in ranked order (a skipped family: `<id>-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=<r>`, `<r>` the gate's reason, `untrusted` for `usable=true review=false`, `no-session-id` when `CLAUDE_CODE_SESSION_ID` is unset), then `panel tier=<t> lists=<n>` (`<n>` counts `OK` and `FALLBACK`). Bound: `max(first-row seconds + grace) + 120`, grace 60 for codex and 70 for agy; exit 0 when it answered, 2 on a usage error.
- **C11 `review-route` seats:** task at risk 0-2 with either surface open: `primary=panel:light fallback=<band seat> reason=band`; risk 3: `primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk`; plan round 1: `primary=panel:plan fallback=dforge:judge-opus reason=round cap=<n>`; neither surface open: the Claude seat with `reason=reviewers-off`. A surface is open when `executor_session_on codex review` or `executor_session_on agy review` succeeds.
- **C12 `task-step review` output:** files `task-N-review-prompt.md` (judge) and `task-N-review-panel-prompt.md` (reviewers), out dir `task-N-review-panel/`; lines `seat: panel:light prompt: <judge prompt> fallback: <seat>` or `seat: panel:heavy+judge-opus prompt: <judge prompt> then: dforge:judge-opus`, then `panel: <command>` and `timeout: <ms>`, where ms = (max over both judge blocks' rows of the tier of seconds + grace, + 120) × 1000: light `2590000`, heavy `5590000`. The judge prompt's Second Pass placeholder is `[EXTERNAL_REVIEW_FILES]`, filled with one path per line; the report's external section is `## External findings`, which `task-step verdict` reads in place of `## Codex findings`.
- **C13 plan-lint obsolete-line warning:** `WARN Task <N>: the **Executor:** line is obsolete; the session implements this task`. A `> **External executors:**` header line is accepted silently.
- **C14 `reference/external-review.md`:** replaces `reference/executor-lane.md`; every link to the old file points at it.

## Assumptions (evidence)

- agy 1.5.7 is installed, `agy --help` lists `--mode` (`accept-edits`, `auto`, `plan`), `--json-schema`, `--add-dir` and `--print-timeout` (run 2026-11-13).
- `agy models` offers `claude-opus-5-5-high` and `gemini-4-argon-high` (run 2026-11-13).
- `agy -p --mode plan` answers in print mode with schema-valid JSON and writes nothing: unverified — Task 1 verifies it with the two real runs.
- `scripts/release.mjs --dry-run` exists (`scripts/release.mjs:8`) and bumps to `<major+1>.0.0` when a pending commit subject matches `^\w+(\([^)]*\))?!:` (`scripts/release.mjs:29-33`); version lines are touched only by releases, so A18 is checked through its dry run, not by a hand bump.
- No marketplace file holds a dforge version (`.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`); the version lives in `plugins/dforge/.claude-plugin/plugin.json` and `plugins/dforge/.codex-plugin/plugin.json` only.
- `scripts/lib/task-state.sh`'s `dr_snapshot` is also used by the Codex-host judge snapshot recipe (`reference/native-codex.md:282-284`), so it moves to `scripts/lib/snapshot.sh` rather than being deleted.
- The final review's dedupe origin tag (`reference/final-review.md:325`) is read by no script (search of `plugins/dforge/scripts` 2026-11-13), so A15's tag set is prose; A15's script side is the panel's `--kind final` run in Task 9.
- `executors ranked` orders agy (priority 10) before codex (20) (`scripts/executors:78-96`); the panel keeps that order.
- The full suite has no recorded run in this worktree's `suites.tsv`; the primary checkout records 173-347 s, so the Task check is rule 4.
- Borderline review scores (round 2: executability 12, coherence 14 is clear, assumptions 12): accepted. Round 2's one Critical and four Important findings were fixed after it, at the cap; the remaining risk is test snippets meeting suite helpers, which each task's Step 2 (the test must fail for the stated reason) catches before implementation.

## Task index

1. agy review runner and plan-mode verification
2. task-step, review-route and next-step ignore Executor lines
3. Delete the lane runners and their suites
4. plan-lint warns on Executor lines; lane blocks go
5. Plan library, task-brief and revising-plans retire
6. Review-only registry and one probe per runner
7. codex-gate keeps only the review surface
8. agy-gate becomes a review gate with agyReview
9. The review panel runner
10. review-route routes reviews to the panel
11. task-step runs the panel and reads External findings
12. References describe external review
13. Skills drop the executor lane
14. Release surface and the lane-name guard

---

### Task 1: agy review runner and plan-mode verification

**Files:**
- Create: `plugins/dforge/scripts/run-agy-review.sh`
- Create: `plugins/dforge/scripts/lib/snapshot.sh`
- Create: `plugins/dforge/criteria/agy-final-review-schema.json`
- Create: `plugins/dforge/tests/agy-review.test.sh`
- Modify: `plugins/dforge/scripts/lib/task-state.sh` (source `snapshot.sh` in place of the moved functions)
- Modify: `plugins/dforge/reference/ladder.md` (add the `agy-judge` block after the `codex-judge` section)
- Modify: `plugins/dforge/reference/native-codex.md:282-284` (source `scripts/lib/snapshot.sh`)
- Modify: `plugins/dforge/tests/fixtures/stub-agy/agy` (review modes)
- Modify: `plugins/dforge/reference/agy-policy.json`
- Modify: `scripts/test-shards.mjs` (weight for `agy-review.test.sh`)
- Modify: `plugins/dforge/tests/agy-gate.test.sh:80-81` (policy pin, when Step 5 moves the version floor)

**Interfaces:**
- Consumes: the existing `agy-gate` line (`usable=`, `fallback=`) and `scripts/lib/executor-session.sh` (`executor_session_mark_off`, `executor_session_mark_fallback_off`).
- Produces: C1, C2, C3, C4, C5.

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Extend the stub agy first, in `tests/fixtures/stub-agy/agy`, before its `case "${STUB_AGY_MODE:-done}"`:

```bash
model=""; prev=""
for arg in "$@"; do [ "$prev" = --model ] && model="$arg"; prev="$arg"; done
if [ -n "${STUB_AGY_REFUSE_MODEL:-}" ] && [ "$model" = "$STUB_AGY_REFUSE_MODEL" ]; then
  printf '{"conversation_id":"","status":"ERROR","response":"","error":"unknown model: %s","finished_reason":"error"}\n' "$model"
  exit 1
fi
side() {
  case "${STUB_AGY_SIDE:-}" in
    write) write_file ;;
    commit) write_file; git add -A && git commit -qm stub ;;
    stash) write_file; git stash -q -u ;;
  esac
}
review_json() { printf '{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"PASS","task_quality":"PASS","findings":[%s],"cannot_verify":[]}' "${STUB_AGY_FINDING:-}"; }
```

and these arms inside the case:

```bash
  review) side; printf '{"conversation_id":"c","status":"SUCCESS","response":"ok","structured_output":%s}\n' "$(review_json)" ;;
  plan-review) side; printf '{"conversation_id":"c","status":"SUCCESS","response":"ok","structured_output":{"executability":18,"coherence":18,"coverage":18,"assumptions":18,"findings":[]}}\n' ;;
  final-review) side; printf '{"conversation_id":"c","status":"SUCCESS","response":"ok","structured_output":{"review":"No findings."}}\n' ;;
  stderr-quota) printf '{"conversation_id":"","status":"ERROR","response":"","error":"","finished_reason":"error"}\n'; printf '429 Too Many Requests\n' >&2; exit 1 ;;
```

Then create `tests/agy-review.test.sh`:

```bash
#!/usr/bin/env bash
# run-agy-review.sh is the agy reviewer. Every case runs the stub agy behind
# the real agy-gate, in a throwaway repository and session directory.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
RUN="$P/scripts/run-agy-review.sh"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" DR_AGY_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=s1
export DR_AGY_POLICY="$TMP/policy.json" STUB_AGY_ARGS_LOG="$TMP/args"
mkdir -p "$HOME" "$TMP/work"
cp "$P/reference/agy-policy.json" "$DR_AGY_POLICY"
printf '# r\n' > "$TMP/prompt.md"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
git -C "$TMP/work" init -q && git -C "$TMP/work" config user.name t && git -C "$TMP/work" config user.email t@t
git -C "$TMP/work" commit -q --allow-empty -m base
export PATH="$P/tests/fixtures/stub-agy:$PATH"
# A stub gate line, not the real gate: the real gate's probe spawns the stub
# from Node, which Windows Git Bash cannot do.
GATE_ON='agy-gate usable=true reason=ok review=false lane=false resets_at=- fallback=on fallback_resets_at=- source=cache'
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${GATE_LINE:-%s}"\n' "$GATE_ON" > "$TMP/gate"; chmod +x "$TMP/gate"
run() { # run <args...>; sets out, rc
  rm -f "$TMP/args"
  out=$(cd "$TMP/work" && AGY_REVIEW_GRACE=5 AGY_REVIEW_GATE="$TMP/gate" bash "$RUN" --cwd "$TMP/work" --out "$TMP/out.json" "$@" 2>"$TMP/err"); rc=$?
}
args() { tr '\n' ' ' < "$TMP/args" 2>/dev/null; }
field() { jq -r ".$1 | tostring" "$DR_AGY_SESSION_DIR/s1.json" 2>/dev/null | tr -d '\r'; }

STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
check "light review answers OK" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out.json evidence=none"
check "light review exits 0" "$rc" "0"
has "the reviewer runs in plan mode" "$(args)" "--mode plan"
has "the task schema is enforced" "$(args)" "codex-review-schema.json"
has "the prompt directory is added" "$(args)" "--add-dir"
lacks "permissions are never skipped" "$(args)" "--dangerously-skip-permissions"
check "the list lands in --out" "$(jq -r .spec_verdict "$TMP/out.json")" "PASS"

STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
check "heavy review prefers agy Opus" "$out" "agy-judge claude-opus-5-5/high status=OK exit=0 out=$TMP/out.json evidence=none"
STUB_AGY_REFUSE_MODEL=claude-opus-5-5 STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
has "a refused Opus falls back to Argon" "$out" "agy-judge gemini-4-argon/high status=FALLBACK"
STUB_AGY_REFUSE_MODEL=gemini-4-argon STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "the light tier never falls back" "$out" "status=FAILED"
has "a refusal names its reason" "$out" "reason=refused"

for side in write commit stash; do
  git -C "$TMP/work" stash clear; git -C "$TMP/work" clean -qfd
  STUB_AGY_SIDE=$side STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
  has "a reviewer that does $side fails" "$out" "status=FAILED"
  has "a $side run is evidence=wrote" "$out" "evidence=wrote reason=wrote"
  check "a $side run names what changed" "$([ -s "$TMP/out.json.wrote" ] && echo named || echo none)" "named"
  case $side in
    commit) check "a commit names HEAD" "$(grep -cx HEAD "$TMP/out.json.wrote")" "1" ;;
    stash) check "a stash names the stash list" "$(grep -cx stash "$TMP/out.json.wrote")" "1" ;;
  esac
done
git -C "$TMP/work" stash clear; git -C "$TMP/work" clean -qfd

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_FINDING='{"severity":"Minor","where":"a","what":"quota wording"}' STUB_AGY_MODE=review run --kind task --tier light --prompt "$TMP/prompt.md"
has "a clean answer mentioning quota is a list" "$out" "status=OK"
check "a clean answer marks nothing" "$([ -f "$DR_AGY_SESSION_DIR/s1.json" ] && echo marked || echo none)" "none"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=stderr-quota run --kind task --tier light --prompt "$TMP/prompt.md"
has "a stderr-only quota fails the run" "$out" "reason=quota-stderr"
check "a stderr-only quota marks nothing" "$([ -f "$DR_AGY_SESSION_DIR/s1.json" ] && echo marked || echo none)" "none"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='request 14290 failed' run --kind task --tier light --prompt "$TMP/prompt.md"
has "429 inside a number is no quota" "$out" "reason=error"

STUB_AGY_MODE=print-timeout run --kind task --tier light --prompt "$TMP/prompt.md"
has "a print timeout is TIMEOUT" "$out" "status=TIMEOUT"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota for claude. Resets in 2h' run --kind task --tier heavy --prompt "$TMP/prompt.md"
has "a Claude quota fails the Opus run" "$out" "agy-judge claude-opus-5-5/high status=FAILED"
check "a Claude quota marks the Claude row" "$(field fallback.on)" "false"
check "a Claude quota leaves agy usable" "$([ "$(field usable)" = false ] && echo off || echo on)" "on"
GATE_LINE="${GATE_ON/fallback=on/fallback=off}" STUB_AGY_MODE=review run --kind task --tier heavy --prompt "$TMP/prompt.md"
check "the next heavy review runs Argon directly" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out.json evidence=claude-off"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota' run --kind task --tier light --prompt "$TMP/prompt.md"
check "a Gemini quota turns agy off" "$(field usable)/$(field reason)" "false/quota"

rm -rf "$DR_AGY_SESSION_DIR"; STUB_AGY_MODE=plan-review run --kind plan --prompt "$TMP/prompt.md"
has "a plan review uses the plan schema" "$(args)" "codex-plan-review-schema.json"
has "a plan review takes the heavy row" "$out" "claude-opus-5-5/high status=OK"
STUB_AGY_MODE=final-review run --kind final --base HEAD
has "a final review uses its schema" "$(args)" "agy-final-review-schema.json"
check "a final review writes its text" "$(cat "$TMP/out.json")" "No findings."

run --kind task
check "a task review without --prompt is a usage error" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

The `field fallback.on` path assumes the session file's Claude mark lives at `.fallback.on`; read `executor_session_mark_fallback_off` in `scripts/lib/executor-session.sh` and use its real key in that one check if it differs.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/agy-review.test.sh`
Expected: FAIL — `run-agy-review.sh` does not exist.

- [ ] **Step 3: Implement**

1. `scripts/lib/snapshot.sh`: move `dr_state_error`, `dr_canonical`, `_dr_submodule_head`, `_dr_is_gitlink`, `_dr_snapshot_entries`, `dr_snapshot` and `dr_task_assert_snapshot` verbatim out of `scripts/lib/task-state.sh`; `task-state.sh` sources `snapshot.sh` from its own directory. In `reference/native-codex.md:282-284`, source `scripts/lib/snapshot.sh` instead of `task-state.sh`.
2. `reference/ladder.md`: after the `codex-judge` section add a short `agy-judge` section and the fenced block of C2, saying the first row is preferred, the last is the fallback and the light tier, and that the bounds copy the Codex rows of the same tier.
3. `criteria/agy-final-review-schema.json`: C4.
4. `scripts/run-agy-review.sh`, modelled on `scripts/run-codex-review.sh` (flag parsing, `die` with exit 2, absolute `--out`/`--cwd`/`--prompt`, the judge rows read from the `agy-judge` block of `AGY_REVIEW_LADDER`):
   - Gate: run `AGY_REVIEW_GATE`; require ` usable=true ` (read nothing else, so a run works while `trust.review` is pending); otherwise print `agy-judge none/none status=FAILED exit=0 out=<out> evidence=none reason=gate` and exit 1. When the chosen row is a `claude-*` model and the line lacks ` fallback=on `, use the last row instead and set `evidence=claude-off`.
   - Rows: light tier → last row only; heavy, plan, final → first row, one fallback to the last row on `refused`.
   - Schema: task kinds `criteria/codex-review-schema.json`, plan `criteria/codex-plan-review-schema.json`, final `criteria/agy-final-review-schema.json`. For `final`, write a prompt file next to `--out` holding `criteria/codex-final-review.md` and the line `Review the branch diff from <base> to HEAD.`.
   - Invocation: `agy --mode plan --output-format json --json-schema <native schema path> --model <m> --effort <e> --add-dir <native prompt dir> --print-timeout <secs>s -p "Your complete instructions are in <native prompt path>. Read the whole file first and follow it."`, stdin from `/dev/null`, in `--cwd`, under `setsid timeout -k 10 $((secs + GRACE))` where `setsid` exists, else plain `timeout -k 10`. Native paths through `dr_native_path`.
   - Write check: `dr_snapshot` of `--cwd` plus `git stash list` before and after; any difference in `.files`, `.head` or the stash list ends `status=FAILED … evidence=wrote reason=wrote` and writes the changed paths (`HEAD`, `stash` for those two) to `<out>.wrote`.
   - Classification, carried from `scripts/run-agy-task.sh` (read it: the print-timeout test, the cause selection that never scans a clean JSON answer, `is_quota` with the whole-number `429`, the unknown-model test, the `Resets in` parse): `finished_reason == print_timeout` or the outer timer → `TIMEOUT reason=timeout`; an unknown-model cause → `refused`; a quota in `.error` → `FAILED reason=quota`, marking `executor_session_mark_fallback_off agy <epoch>` for a `claude-*` model and `executor_session_mark_off agy quota <epoch>` otherwise (no epoch: for the session); a quota only on stderr → `FAILED reason=quota-stderr`, no mark; a `structured_output` that is not an object, or (task/plan) misses a schema-required key → `FAILED reason=schema`; anything else non-zero → `FAILED reason=error`.
   - Output: `OK`/`FALLBACK` write `structured_output` (task, plan) or its `review` string (final) to `--out`; status line per C1; agy's stdout and stderr go to `<out>.stdout`/`<out>.stderr`.
5. `scripts/test-shards.mjs`: add `'agy-review.test.sh': 60` to `windowsSeconds`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/agy-review.test.sh && timeout 300 bash plugins/dforge/tests/task-state.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS, 0 failed.

- [ ] **Step 5: Verify plan mode with two real runs**

This is the spec's riskiest assumption and A16; the owner consented to exactly these two billed runs. In the worktree:

1. Write `$ws/verify-prompt.md` (`$ws` = `bash plugins/dforge/scripts/sdd-workspace docs/dforge/plans/2026-11-13-reviewer-only-externals.md`): a task-review prompt asking for a review of `HEAD~1..HEAD` of this branch, ending with "Answer with one JSON object matching the schema you were given."
2. Run as a background Bash call with `timeout` 2600000 ms: `bash plugins/dforge/scripts/run-agy-review.sh --kind task --tier light --cwd "$PWD" --out "$ws/verify-argon.json" --prompt "$ws/verify-prompt.md"`.
3. Then, as a background Bash call with `timeout` 5600000 ms: the same with `--tier heavy --out "$ws/verify-opus.json"`; the status line must name `claude-opus-5-5/high`.
4. Both `status=OK` with no `evidence=wrote`: set `reference/agy-policy.json` to `"trust": {"smoke": "pass", "review": "pass"}` and `min_version`/`calibrated` to the `agy --version` printed now (1.5.7 on 2026-11-13); set the stub agy's default `STUB_AGY_VERSION` (`tests/fixtures/stub-agy/agy:12`) to the same version and replace every `1.4.12` in `agy-gate.test.sh` with it (`sed -i 's/1\.4\.12/<version>/g'`; its out-of-range case uses `1.4.11` and stays below the floor), then run `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh` (PASS). Otherwise set `"review": "pending"`, keep the versions, record the failing status line in this plan's Assumptions, and continue: agy review then ships off (spec, Riskiest assumption).

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/run-agy-review.sh plugins/dforge/scripts/lib/snapshot.sh plugins/dforge/scripts/lib/task-state.sh plugins/dforge/criteria/agy-final-review-schema.json plugins/dforge/tests/agy-review.test.sh plugins/dforge/tests/fixtures/stub-agy/agy plugins/dforge/reference/ladder.md plugins/dforge/reference/native-codex.md plugins/dforge/reference/agy-policy.json scripts/test-shards.mjs
git commit -m "feat(dforge): add the agy review runner"
```

### Task 2: task-step, review-route and next-step ignore Executor lines

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`do_start` executor branches `:732-831`, usage comment `:20`)
- Modify: `plugins/dforge/scripts/review-route` (executor block `:367`, `:392-411`; ruling kinds `:310-314`; header comments `:2-11`, `:27-30`)
- Modify: `plugins/dforge/scripts/next-step` (`thread pending` warning `:264-271`)
- Test: `plugins/dforge/tests/review-route.test.sh`, `plugins/dforge/tests/task-step.test.sh`, `plugins/dforge/tests/next-step.test.sh`, `plugins/dforge/tests/task-loop-steps.acceptance.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: an `**Executor:**` line no longer changes any seat, dispatch or warning (A9's task-step half).

**Items:** 6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/review-route.test.sh::executor tasks`**

Replace the executor-specific expectations (`:161-165`, `:184`, `:660-700`, `:745-752`) with one table: the same fixture plan with every `**Executor:**` line removed must route identically.

```bash
sed '/\*\*Executor:\*\*/d' "$TMP/plan.md" > "$TMP/no-executor.md"
for id in 5 6 11; do
  check "an Executor line does not route Task $id" \
    "$(bash "$ROUTE" "$TMP/plan.md" --task "$id" 2>&1 | sed 's/^review-seat [^ ]* //')" \
    "$(bash "$ROUTE" "$TMP/no-executor.md" --task "$id" 2>&1 | sed 's/^review-seat [^ ]* //')"
done
check "executor-empty-diff is no ruling kind" "$(bash "$ROUTE" "$TMP/plan.md" --ruling executor-empty-diff >/dev/null 2>&1; echo $?)" "2"
```

Also: the kind lists at `:263-286` drop `executor-empty-diff` and `codex-empty-diff`; the `reason=executor` expectations at `:335-337` (run with the review surface off) become each task's Claude seat with `reason=codex-off`, the no-executor plan's answer.

In `task-step.test.sh`, replace the executor start case (`:195-201`) with:

```bash
step start docs/plan.md 3 --inline
check "an Executor task takes --inline" "$rc" "0"
check "an Executor task names no executor" "$(grep -c -i 'executor' <<<"$out")" "0"
```

In `next-step.test.sh`, invert the `thread pending` case (`:171-176`): the same ledger now produces no line containing `thread pending`. In `task-loop-steps.acceptance.test.sh`, delete the `executor-empty-diff` routing block (`:423-435`).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh; timeout 600 bash plugins/dforge/tests/task-step.test.sh start; timeout 300 bash plugins/dforge/tests/next-step.test.sh`
Expected: FAIL on the new checks (executor tasks route by `reason=executor`, `--inline` is refused, the warning prints).

- [ ] **Step 3: Implement**

1. `review-route`: drop the `executor=` detection and the two `reason=executor` arms; the chain starts at the `codex-off` test. Remove `executor-empty-diff` and `codex-empty-diff` from the ruling kinds (an unknown kind already exits 2). Update the header comments to match.
2. `task-step`: delete `exec_id` and every branch reading it in `do_start` (`plan_executors` call, the `--inline` refusal, the skipped assigned line and dispatch file, the two executor messages) and the usage sentence at `:20`.
3. `next-step`: delete the `thread pending)` warning and the `plan-revise` comment at `:88`; keep the generic assigned-line warning.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh && timeout 900 bash plugins/dforge/tests/task-step.test.sh && timeout 300 bash plugins/dforge/tests/next-step.test.sh && timeout 600 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/scripts/review-route plugins/dforge/scripts/next-step plugins/dforge/tests/review-route.test.sh plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/next-step.test.sh plugins/dforge/tests/task-loop-steps.acceptance.test.sh
git commit -m "refactor(dforge): stop routing by Executor lines"
```

### Task 3: Delete the lane runners and their suites

**Files:**
- Delete: `plugins/dforge/scripts/run-codex-task.sh`, `plugins/dforge/scripts/run-agy-task.sh`, `plugins/dforge/scripts/lane-breaker`, `plugins/dforge/scripts/lib/task-execution.sh`, `plugins/dforge/reference/external-task-recovery.md`, `plugins/dforge/scripts/codex-task-contract.md`, `plugins/dforge/scripts/agy-task-contract.md`, `plugins/dforge/scripts/codex-report-schema.json`, `plugins/dforge/scripts/agy-report-schema.json`
- Modify: `plugins/dforge/tests/executors.test.sh` (`:94-95`, `:110-111` expect the review runners as `wrapper`) and `plugins/dforge/tests/fixtures/executors/codex.json` (kept byte-identical to the shipped entry, `:183-184`)
- Delete: `plugins/dforge/tests/run-codex-task.test.sh`, `executor-recovery.test.sh`, `run-agy-task.test.sh`, `lane-breaker.test.sh`, `task-state.test.sh`, `antigravity-executor-lane.acceptance.test.sh`, `agy-gemini-first.acceptance.test.sh`
- Modify: `plugins/dforge/scripts/lib/task-state.sh` (keep only what `snapshot.sh` does not hold and something still sources; delete the file when nothing does)
- Modify: `plugins/dforge/tests/lanes.test.sh` (keep the `codex-judge` pins `:143-185` minus the `codex-timeout` drift check; add the same pins for `agy-judge`; delete every lane-block case)
- Modify: `plugins/dforge/scripts/lib/codex-client.mjs:233-237` and `plugins/dforge/scripts/run-codex-review.sh` `run_seat` (drop `resumeThreadId`, `persistThread`, `threadName`), `plugins/dforge/tests/codex-client.test.sh` (`:32`, `:58-81`)
- Modify: `plugins/dforge/reference/executors/codex.json`, `agy.json` (`wrapper` → `scripts/run-codex-review.sh` / `scripts/run-agy-review.sh`)
- Modify: `scripts/test-shards.mjs`, `scripts/test-all.mjs` (drop the deleted suites)

**Interfaces:**
- Consumes: C3 (`snapshot.sh`), C1 (the agy runner path).
- Produces: no lane runner exists; the registry's `wrapper` names the review runners until Task 6 renames the field.

**Items:** 1, 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/lanes.test.sh::judge blocks`**

```bash
for blk in codex-judge agy-judge; do
  rows=$(awk -v b="$blk" '$0 == "```" b { f = 1; next } f && $0 == "```" { exit } f && NF' "$P/reference/ladder.md")
  check "$blk has two rows" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "2"
  check "$blk rows are model effort seconds" "$(printf '%s\n' "$rows" | awk 'NF != 3 || $3 !~ /^[0-9]+$/' | wc -l | tr -d ' ')" "0"
done
check "agy-judge prefers Opus" "$(awk '$0 == "```agy-judge" { getline; print $1; exit }' "$P/reference/ladder.md")" "claude-opus-5-5"
check "no lane runner remains" "$(ls "$P/scripts" | grep -c -e '^run-codex-task' -e '^run-agy-task' -e '^lane-breaker')" "0"
```

In `codex-client.test.sh`, the forward case asserts that the request reaching the plugin has no `resumeThreadId`, `persistThread` or `threadName` key.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh; timeout 300 bash plugins/dforge/tests/codex-client.test.sh`
Expected: FAIL on "no lane runner remains" and the thread-field case.

- [ ] **Step 3: Implement**

1. `git rm` every file listed under Delete; drop their entries from `windowsSeconds` (`scripts/test-shards.mjs`) and from `suiteSeconds`/`suiteParts` (`scripts/test-all.mjs`), and the header comments naming them (`scripts/test-shards.mjs:10-18`).
2. `task-state.sh`: after the deletions, `git grep -n 'task-state.sh' plugins/dforge` lists the remaining sourcers; delete the file if none remain, else keep only the functions they call.
3. `codex-client.mjs`: stop forwarding the three thread options; keep `threadId`/`turnId` capture (the interrupt needs them) and drop the `run-codex-task.sh` comment at `:134`. `run-codex-review.sh`: drop the three fields from `run_seat`'s request.
4. Registry `wrapper` values as listed; `lanes.test.sh` as Step 1.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/lanes.test.sh && timeout 300 bash plugins/dforge/tests/codex-client.test.sh && timeout 300 bash plugins/dforge/tests/codex-review.test.sh && timeout 300 bash plugins/dforge/tests/detect.test.sh && timeout 300 bash plugins/dforge/tests/executors.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Then the Integration check (tasks 1-3 checkpoint).
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge scripts/test-shards.mjs scripts/test-all.mjs
git commit -m "refactor(dforge)!: retire the external executor lane" -m "BREAKING CHANGE: Codex and agy no longer implement plan tasks; run-codex-task.sh, run-agy-task.sh and lane-breaker are removed."
```

### Task 4: plan-lint warns on Executor lines; lane blocks go

**Files:**
- Modify: `plugins/dforge/scripts/plan-lint` (`:9-10`, `:19`, `:274-342`, `:413-508`, `:540-563`, `:598`, `:622`)
- Modify: `plugins/dforge/reference/ladder.md` (delete blocks `gate`, `codex-assignment`, `codex-successor`, `codex-timeout`, `agy-lane-gate`, `agy-assignment`, `agy-successor`, `agy-timeout` and their sections; keep the "about 500k tokens" Claude-quota fact, moved into the `agy-judge` section; rewrite §"The external lane" `:225-232` as a short judge-only intro and `codex-judge`'s rationale `:349-361` without the lane)
- Modify: `plugins/dforge/reference/executors/codex.json`, `agy.json` (`blocks` keeps only `judge`: `codex-judge`, `agy-judge`), `plugins/dforge/scripts/executors` (`valid_entry` no longer requires `blocks.gate`)
- Modify: `plugins/dforge/tests/fixtures/executors/*.json`, `plugins/dforge/tests/fixtures/stub-ladder.md`
- Test: `plugins/dforge/tests/plan-lint.test.sh`, `plugins/dforge/tests/executors.test.sh`, `plugins/dforge/tests/inline-mode.test.sh`, `inline-only.acceptance.test.sh`, `inline-only-execution.acceptance.test.sh`, `faster-plans.acceptance.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C13.

**Items:** 1, 2, 6

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Replace the plan-lint lane sections (`:48-67` stubs, `:476-485`, `:579-620`, `:827-1049`, `:1099-1103`) with:

```bash
tplan "$TMP/clean-plan.md" inline sonnet low 2 2
sed -e '/^## Global Constraints/i\
> **External executors:** [x] codex\
' -e '/^### Task 2/,/^\*\*Evaluation:/{/^\*\*Evaluation:/a\
**Executor:** codex gpt-6.1-sol / low
}' "$TMP/clean-plan.md" > "$TMP/exec-plan.md"
check "the clean plan lints clean" "$(bash "$P/scripts/plan-lint" "$TMP/clean-plan.md" >/dev/null 2>&1; echo $?)" "0"
out=$(bash "$P/scripts/plan-lint" "$TMP/exec-plan.md" 2>&1); rc=$?
check "an Executor line is no error" "$rc" "0"
check "an Executor line gets one warning" \
  "$(grep -c '^WARN Task 2: the \*\*Executor:\*\* line is obsolete; the session implements this task$' <<<"$out")" "1"
check "the External executors header is accepted silently" "$(grep -c 'External executors' <<<"$out")" "0"
check "an Executor line raises no effort floor" "$(grep -c -i 'delegated' <<<"$out")" "0"
```

`tplan` is the suite's own one-clean-task-per-total helper (`plan-lint.test.sh:316`). In `executors.test.sh`, the shipped-entry cases assert `blocks` keys are exactly `judge` (`jq -r '.blocks | keys | join(",")'` → `judge`) and drop the lane-block loop (`:124`). In the inline-* and faster-plans suites, delete the cases that assert executor delegation, `reason=executor`, the delegated NOTE or the External executors header.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/plan-lint.test.sh; timeout 300 bash plugins/dforge/tests/executors.test.sh`
Expected: FAIL — plan-lint validates the Executor line against the lane gate; `blocks` still holds lane keys.

- [ ] **Step 3: Implement**

1. `plan-lint`: delete the executor field/gate/rung helpers, the `lane_gates` table, the External-executors header parsing and its error, the per-task lane checks, the lazy lane probe and its WARN, the R5 delegated NOTE and the executor effort raise, the parent-line NOTE, and the waves "must run alone" executor clause. A task with an `**Executor:**` line gets C13's WARN once. `--no-probe` stays accepted and does nothing (skills pass it). Drop the `executor-session.sh` source if nothing else in plan-lint uses it.
2. `ladder.md`, the registry `blocks`, `scripts/executors` and the fixtures as listed.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/plan-lint.test.sh && timeout 300 bash plugins/dforge/tests/executors.test.sh && timeout 600 bash plugins/dforge/tests/inline-mode.test.sh && timeout 600 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/inline-only-execution.acceptance.test.sh && timeout 900 bash plugins/dforge/tests/faster-plans.acceptance.test.sh && timeout 300 bash plugins/dforge/tests/lanes.test.sh`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "refactor(dforge): warn on obsolete Executor lines"
```

### Task 5: Plan library, task-brief and revising-plans retire

**Files:**
- Modify: `plugins/dforge/scripts/lib/plan.sh` (delete `plan_executors` `:204-235`, `plan_delegated` `:242-251`, the `DR_LADDER` seam comment `:82-83` if unused)
- Modify: `plugins/dforge/scripts/task-brief` (`:48-54`, `:63`, `:68-71`, `:84-89`)
- Delete: `plugins/dforge/scripts/plan-revise`, `plugins/dforge/skills/revising-plans/`, `plugins/dforge/tests/plan-revise.test.sh`
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md:30` (delete the revising-plans routing row), `plugins/dforge/README.md` (every `dforge:revising-plans` and `plan-revise` mention outside the "Migrating to 4.11" section, which Task 14 rewrites)
- Modify: `scripts/test-shards.mjs`, `scripts/test-all.mjs` (drop `plan-revise.test.sh`)
- Test: `plugins/dforge/tests/plan-lib.test.sh` (`:170-260`), the task-brief suite (`git grep -l task-brief plugins/dforge/tests`)

**Interfaces:**
- Consumes: Tasks 2 and 4 removed every caller of `plan_executors` and `plan_delegated`.
- Produces: A9's task-brief half.

**Items:** 6

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Extend the test `plugins/dforge/tests/plan-lib.test.sh::plan functions`**

Replace the `plan_executors`/`plan_delegated` cases with:

```bash
check "plan_executors is gone" "$(bash -c ". '$P/scripts/lib/plan.sh'; declare -F plan_executors plan_delegated | wc -l" | tr -d ' ')" "0"
```

and in the task-brief suite add, for a plan whose Task 1 carries `**Executor:** codex gpt-6.1-sol / low`:

```bash
out=$(bash "$P/scripts/task-brief" "$TMP/exec-plan.md" 1 2>&1)
check "task-brief briefs an Executor task as an inline task" "$(grep -c 'delegated' <<<"$out")" "0"
```

(write `exec-plan.md` in that suite from its own fixture plan plus that one line).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/plan-lib.test.sh` and the task-brief suite
Expected: FAIL — the functions exist; the brief prints `**Dispatch:** delegated`.

- [ ] **Step 3: Implement**

Delete the two functions and the task-brief delegated branches (keep `**Review:** per-task — risk 3`). `git rm` the plan-revise script, skill directory and suite; drop their weights; delete the routing row and README mentions so `node scripts/validate-repository.mjs` resolves every `dforge:` name.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/plan-lib.test.sh && timeout 60 node scripts/validate-repository.mjs && timeout 120 node --test tests/test-shards.test.mjs` and the task-brief suite
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge scripts/test-shards.mjs scripts/test-all.mjs
git commit -m "refactor(dforge): remove revising-plans and plan-revise"
```

### Task 6: Review-only registry and one probe per runner

**Files:**
- Modify: `plugins/dforge/reference/executors/codex.json`, `agy.json` (`wrapper` → `runner`; `surfaces: ["review"]`)
- Modify: `plugins/dforge/scripts/executors` (`valid_entry` per C6)
- Modify: `plugins/dforge/scripts/detect-executors.sh` (C7; check `runner`; delete `path_row cursor-agent`/`opencode` and the unregistered-id branch)
- Modify: `plugins/dforge/scripts/run-codex-review.sh` (roster call `detect-executors.sh codex`; ` reason=<token>` on every non-`OK` status line, C5)
- Modify: `plugins/dforge/tests/fixtures/executors/*.json` (`runner`, `gate`; delete `opencode.json` or give it `gate`, whichever its remaining users need)
- Test: `plugins/dforge/tests/executors.test.sh`, `plugins/dforge/tests/detect.test.sh`, `plugins/dforge/tests/codex-review.test.sh`, `plugins/dforge/tests/executor-session.test.sh` (`:32-38` lane-surface cases)

**Interfaces:**
- Consumes: C1 (agy runner path), C5.
- Produces: C6, C7, C5 on the Codex runner.

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/codex-review.test.sh::roster`**

Replace the stub roster (`detect-stub`, `:73-83`) so it logs its arguments to `$TMP/roster.log`, then:

```bash
: > "$TMP/roster.log"; out=$(seat task --tier light --out "$TMP/o.json" --prompt "$TMP/p.txt")
check "the runner probes only its own family" "$(cat "$TMP/roster.log")" "codex"
out=$(STUB_MODE=hang seat task --tier light --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a timeout names its reason" "$out" "reason=timeout"
```

In `executors.test.sh`, the shipped entries assert `jq -r '[.runner, (.surfaces|join(","))] | join(" ")'` is `scripts/run-codex-review.sh review` and `scripts/run-agy-review.sh review`, and an entry without `runner` or `gate` is rejected. In `detect.test.sh`, the row ids are `agy,codex` (`:80`) and `bash "$P/scripts/detect-executors.sh" codex | jq -r '[.[].id]|join(",")'` is `codex`; delete the cursor-agent/opencode cases (`:189-206`, `:277-292`). In `executor-session.test.sh`, delete the `lane` surface cases.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/codex-review.test.sh; timeout 300 bash plugins/dforge/tests/executors.test.sh; timeout 300 bash plugins/dforge/tests/detect.test.sh`
Expected: FAIL — the roster gets no id, entries still carry `wrapper`, PATH rows still print.

- [ ] **Step 3: Implement**

As listed under Files. `detect-executors.sh` with arguments iterates only those ids (an unregistered id is a usage error, exit 2); the "registered but its wrapper is missing" row reads `runner`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/codex-review.test.sh && timeout 300 bash plugins/dforge/tests/executors.test.sh && timeout 300 bash plugins/dforge/tests/detect.test.sh && timeout 300 bash plugins/dforge/tests/executor-session.test.sh && timeout 300 bash plugins/dforge/tests/agy-review.test.sh`
Then the Integration check (tasks 4-6 checkpoint).
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "refactor(dforge): make the registry review-only"
```

### Task 7: codex-gate keeps only the review surface

**Files:**
- Modify: `plugins/dforge/scripts/codex-gate` (`:14-16`, `:40-46`, `:97-117`)
- Modify: `plugins/dforge/reference/codex-plugin.json` (`trust` keeps only `calibration`)
- Modify: `plugins/dforge/config/schema.mjs` (delete `codexLane` `:110-114`)
- Test: `plugins/dforge/tests/codex-gate.test.sh`, `plugins/dforge/tests/dforge-config.test.sh` (`:151-152`, `:163`, `:338`), `plugins/dforge/tests/hook.test.sh:179`, and every gate stub line carrying `lane=` (`git grep -n 'lane=' plugins/dforge/tests`)

**Interfaces:**
- Consumes: none.
- Produces: C8 (Codex line).

**Items:** 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/codex-gate.test.sh::lines`**

Every expected line drops ` lane=<b>`, for example:

```bash
check "a usable but untrusted plugin opens no surface" "$out" \
  "codex-gate usable=true reason=ok review=false resets_at=- source=probe"
```

The `codexLane` settings cases (`:263-279`) become:

```bash
setting '{"codexReview":false}'; fresh; gate usable
check "codexReview off answers setting without probing" "$out" "codex-gate usable=false reason=setting review=false resets_at=- source=setting"
check "codexReview off starts no client" "$(grep -c connect "$TMP/log" 2>/dev/null || echo 0)" "0"
setting '{"codexReview":true,"codexLane":true}'; fresh; gate usable
check "a stored codexLane is ignored" "$(grep -c 'reason=setting' <<<"$out")" "0"
```

The policy pin (`:48-49`) expects `trust` keys `calibration` only; the session-reader cases drop `on … lane`. In `dforge-config.test.sh`, `codexLane` leaves the defaults and key rows, and `:338` sets `codexReview` instead. `hook.test.sh:179`'s fixture uses `"codexReview":false`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/codex-gate.test.sh; timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — lines still carry `lane=`; `codexLane` is still a schema key.

- [ ] **Step 3: Implement**

`codex-gate` drops the lane surface: no `codexLane` read, no `trust.smoke`, no `lane` field in the line or the session file; `codexReview` off answers `reason=setting` without probing. Delete `codexLane` from the schema and `smoke` from `codex-plugin.json`. Update gate stub lines in other suites to the new grammar.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/codex-gate.test.sh && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 300 bash plugins/dforge/tests/hook.test.sh && timeout 300 bash plugins/dforge/tests/codex-review.test.sh && timeout 900 bash plugins/dforge/tests/task-step.test.sh`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "refactor(dforge): drop the Codex lane surface"
```

### Task 8: agy-gate becomes a review gate with agyReview

**Files:**
- Modify: `plugins/dforge/scripts/agy-gate` (`:17-19`, `:43-51`, `:95-161`)
- Modify: `plugins/dforge/scripts/run-agy-review.sh` (read ` claude=on ` in place of ` fallback=on `)
- Modify: `plugins/dforge/reference/agy-policy.json` (drop `smoke`)
- Modify: `plugins/dforge/config/schema.mjs` (delete `agyLane` `:120-124`; add C9 right after `codexReview`; `executionMode` description loses ", executor tasks excepted")
- Modify: `plugins/dforge/README.md:981-983` (settings table rows)
- Test: `plugins/dforge/tests/agy-gate.test.sh`, `plugins/dforge/tests/dforge-config.test.sh` (`:165`, `:181-183`), `plugins/dforge/tests/cockpit.test.ts:5767`

**Interfaces:**
- Consumes: C8 grammar from Task 7.
- Produces: C8 (agy line), C9.

**Items:** 4, 7

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/agy-gate.test.sh::lines`**

Every expected line takes the C8 agy grammar, for example:

```bash
check "no agy on PATH turns the gate off" "$out" \
  "agy-gate usable=false reason=plugin-not-installed review=false resets_at=- claude=on claude_resets_at=- source=probe"
```

The fixture registry (`:153-160`) uses `surfaces:["review"], blocks:{judge:"agy-judge"}, runner:"scripts/run-agy-review.sh"`. Settings and trust cases:

```bash
setting '{}'; fresh; gate
check "agyReview unset answers setting without probing" "$out" "agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting"
check "agyReview unset never runs agy" "$([ -f "$ARGS" ] && echo ran || echo none)" "none"
setting '{"agyReview":true}'
jq '.trust = {"review":"pending"}' "$P/reference/agy-policy.json" > "$TMP/pending.json"
fresh; GATE_POLICY="$TMP/pending.json" gate
check "a pending review trust keeps the surface shut" "$(grep -o 'usable=[a-z]* reason=[a-z]* review=[a-z]*' <<<"$out")" "usable=true reason=ok review=false"
jq '.trust = {"review":"pass"}' "$P/reference/agy-policy.json" > "$TMP/pass.json"
fresh; GATE_POLICY="$TMP/pass.json" gate
check "a passed review trust opens the surface" "$(grep -o 'review=[a-z]*' <<<"$out")" "review=true"
setting '{"agyReview":true,"agyLane":false}'; fresh; GATE_POLICY="$TMP/pass.json" gate
check "a stored agyLane is ignored" "$(grep -o 'review=[a-z]*' <<<"$out")" "review=true"
```

Every case that ran with the default `agyLane` on now writes `setting '{"agyReview":true}'` first. In `dforge-config.test.sh`, `:181-183` expects the key after `codexReview` to be `agyReview` labelled `Agy reviews` with default `false`, and `agyLane` leaves the key rows. In `cockpit.test.ts:5767`, press `set-agyReview-toggle`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh; timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL — lines carry `lane=`/`fallback=`; `agyReview` is unknown.

- [ ] **Step 3: Implement**

1. `agy-gate`: read `agyReview` (default false); off → `reason=setting source=setting`, no probe. `review=true` when usable, `agyReview` on and `trust.review == "pass"`. Print the Claude mark as `claude=`/`claude_resets_at=` (the stored session key keeps its name). Write `review` (not `lane`) to the session file.
2. `run-agy-review.sh`: the Claude-row test reads ` claude=on `; `agy-review.test.sh`'s `GATE_ON` line and its `fallback=off` substitution take the C8 agy grammar (`claude=on` / `claude=off`); add `agy-review.test.sh` to this task's commit.
3. Schema, policy and README as listed. The cockpit Workflow tab renders from the schema, so no cockpit source changes.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/agy-gate.test.sh && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 300 bash plugins/dforge/tests/agy-review.test.sh && timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, 0 failed.

- [ ] **Step 5: Demo the cockpit settings (A12)**

Run `timeout 30 node --input-type=module -e "import s from './plugins/dforge/config/schema.mjs'; for (const [k,v] of Object.entries(s)) if (v.group==='Workflow') console.log(k, '|', v.label, '|', v.description)"` (adjust to the default export's shape) and paste the output into the ledger: it lists `Codex reviews` then `Agy reviews`, no `Codex tasks` or `Agy tasks`, and no `executionMode` description mentioning executor tasks.

- [ ] **Step 6: Commit**

```bash
git add -A plugins/dforge
git commit -m "feat(dforge): add the agy review switch"
```

### Task 9: The review panel runner

**Files:**
- Create: `plugins/dforge/scripts/run-review-panel`
- Create: `plugins/dforge/tests/review-panel.test.sh`
- Modify: `scripts/test-shards.mjs` (weight for `review-panel.test.sh`)

**Interfaces:**
- Consumes: C1, C5, C6 (`executors ranked`, `executors path <id> runner|gate`), C8.
- Produces: C10.

**Items:** 3, 5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8
**Lenses:** lang-bash, silent-failures

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# run-review-panel runs every open reviewer family at once. Stub gates and
# stub runners stand in for codex-gate, agy-gate and the two runners.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
PANEL="$P/scripts/run-review-panel"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export CLAUDE_CODE_SESSION_ID=s1
printf '# r\n' > "$TMP/prompt.md"
mkdir -p "$TMP/work"
for fam in codex agy; do
  cat > "$TMP/$fam-gate" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${${fam^^}_GATE_LINE:-$fam-gate usable=true reason=ok review=true resets_at=- source=cache}"
EOF
  cat > "$TMP/$fam-runner" <<EOF
#!/usr/bin/env bash
# Records its start and end times, so the test can see overlap.
args="\$*"; out=""; tier=heavy
while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; --tier) tier="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s start %s\n' $fam "\$(date +%s%N)" >> "$TMP/times"
printf '%s\n' "\$args" > "$TMP/$fam.args"
sleep "\${${fam^^}_SLEEP:-1}"
printf '%s end %s\n' $fam "\$(date +%s%N)" >> "$TMP/times"
printf '{}' > "\$out"
model=\$( [ "\$tier" = light ] && echo $( [ $fam = codex ] && echo gpt-6.1-sol/xhigh || echo gemini-4-argon/high) || echo $( [ $fam = codex ] && echo gpt-6-astra/xhigh || echo claude-opus-5-5/high))
printf '%s-judge %s status=%s exit=0 out=%s evidence=none\n' $fam "\$model" "\${${fam^^}_STATUS:-OK}" "\$out"
EOF
  chmod +x "$TMP/$fam-gate" "$TMP/$fam-runner"
done
export PANEL_CODEX_GATE="$TMP/codex-gate" PANEL_AGY_GATE="$TMP/agy-gate" PANEL_CODEX_RUNNER="$TMP/codex-runner" PANEL_AGY_RUNNER="$TMP/agy-runner"
panel() { rm -f "$TMP/times" "$TMP"/*.args; out=$(bash "$PANEL" --cwd "$TMP/work" --out-dir "$TMP/out" "$@" 2>"$TMP/err"); rc=$?; }

panel --kind task --tier light --prompt "$TMP/prompt.md"
check "light panel prints both reviewers in ranked order and a summary" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out/agy.json evidence=none
codex-judge gpt-6.1-sol/xhigh status=OK exit=0 out=$TMP/out/codex.json evidence=none
panel tier=light lists=2"
check "the panel exits 0" "$rc" "0"
first_end=$(awk '$2 == "end" { print $3; exit }' "$TMP/times")
last_start=$(awk '$2 == "start" { s = $3 } END { print s }' "$TMP/times")
check "both reviewers run at the same time" "$([ "$last_start" -lt "$first_end" ] && echo overlap || echo serial)" "overlap"
check "the light tier reaches the runners" "$(grep -c -- '--tier light' "$TMP/codex.args" "$TMP/agy.args" | awk -F: '{ s += $2 } END { print s }')" "2"

panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "heavy panel runs Astra and agy Opus" "$(grep -c -e 'gpt-6-astra/xhigh status=OK' -e 'claude-opus-5-5/high status=OK' <<<"$out")" "2"

AGY_STATUS=FALLBACK panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a FALLBACK runner counts as a list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"

AGY_GATE_LINE='agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a closed gate skips its family with the gate's reason" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=setting"
check "a skipped family is never started" "$([ -f "$TMP/agy.args" ] && echo started || echo skipped)" "skipped"
AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "an untrusted surface is skipped as untrusted" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=untrusted"
CODEX_GATE_LINE='codex-gate usable=false reason=logged-out review=false resets_at=- source=probe' \
AGY_GATE_LINE='agy-gate usable=false reason=quota review=false resets_at=- claude=on claude_resets_at=- source=cache' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "with both skipped the panel has no list" "$(tail -1 <<<"$out")" "panel tier=light lists=0"
check "with both skipped the panel still exits 0" "$rc" "0"
CLAUDE_CODE_SESSION_ID= AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "no session id is named as the reason" "$(head -1 <<<"$out" | grep -o 'reason=.*')" "reason=no-session-id"

panel --kind final --tier heavy --base HEAD
check "a final panel writes one list per reviewer" "$(ls "$TMP/out" | grep -c '\.md$')" "2"
check "a final panel never passes --tier" "$(cat "$TMP/codex.args" "$TMP/agy.args" | grep -c -- '--tier')" "0"

AGY_STATUS=FAILED panel --kind task --tier light --prompt "$TMP/prompt.md"
check "each runner's stderr has its own file" "$(ls "$TMP/out"/*.stderr | wc -l | tr -d ' ')" "2"

cat > "$TMP/hang-runner" <<EOF
#!/usr/bin/env bash
out=""; while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; *) shift ;; esac; done
sleep 300 & printf '%s\n' \$! > "$TMP/child.pid"; wait
EOF
chmod +x "$TMP/hang-runner"
PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a runner past the bound is reported as TIMEOUT" "$(head -1 <<<"$out")" "agy-judge none/none status=TIMEOUT exit=124 out=$TMP/out/agy.json evidence=none reason=timeout"
if command -v setsid >/dev/null 2>&1; then
  check "the bound kills the runner's children" "$(kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null && echo alive || echo dead)" "dead"
fi

panel --kind task --prompt "$TMP/prompt.md"
check "a task panel without --tier is a usage error" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/review-panel.test.sh`
Expected: FAIL — `run-review-panel` does not exist.

- [ ] **Step 3: Implement**

1. Parse C10's flags (`die` exits 2): `--tier` required for `--kind task`, ignored and not forwarded for plan and final; `--prompt` required for task and plan, `--base` for final; create `--out-dir`.
2. For each id of `scripts/executors ranked`: run its gate (`PANEL_<ID>_GATE`, else `bash "$(bash scripts/executors path <id> gate)"`), last line, `tr -d '\r'`. Not ` review=true ` → print the SKIPPED line of C10 with the reason rule (gate `reason=`, `untrusted` when it printed `usable=true`, `no-session-id` when `CLAUDE_CODE_SESSION_ID` is empty).
3. Start every open family's runner (`PANEL_<ID>_RUNNER`, else the registry `runner`) in the background with `--kind <k> --cwd <cwd> --out <out-dir>/<id>.<json|md> (--prompt|--base) [--tier]`, stdout to `<out-dir>/<id>.status`, stderr to `<out-dir>/<id>.stderr`, under `setsid` where it exists (record the pid as the group id), else as a plain job.
4. Bound per C10 from the `codex-judge`/`agy-judge` rows (`PANEL_LADDER`, else `reference/ladder.md`) of the families started, or `PANEL_BOUND_SECONDS` when set (a test seam); a watchdog kills each runner group still running at the bound (`kill -TERM -<pgid>` where `setsid` exists; without it, `kill -TERM` the runner pid and, where `pkill` exists, `pkill -TERM -P <pid>` repeated for grandchildren — Git Bash may lack `pkill`, so there only the runner pid is signalled, the Known limit the spec states) and the panel prints `<id>-judge none/none status=TIMEOUT exit=124 out=<out file> evidence=none reason=timeout` in that runner's place.
5. Wait for all; print each family's line in ranked order (its runner's last stdout line, or the SKIPPED line), then `panel tier=<tier|heavy for plan/final> lists=<n>`. Exit 0.
6. `scripts/test-shards.mjs`: `'review-panel.test.sh': 30`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/review-panel.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Then the Integration check (tasks 7-9 checkpoint).
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/run-review-panel plugins/dforge/tests/review-panel.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): run external reviewers as a panel"
```

### Task 10: review-route routes reviews to the panel

**Files:**
- Modify: `plugins/dforge/scripts/review-route` (`--plan-round` `:294-297`; task chain `:400-411`; header comments)
- Modify: `evals/controller/lib/transcript.mjs` (`:24-27`, `:197-198`, `:203`)
- Test: `plugins/dforge/tests/review-route.test.sh`, `evals/controller/tests/transcript.test.mjs`

**Interfaces:**
- Consumes: C10 (seat names), the session files both gates write (`executor_session_on <id> review`).
- Produces: C11.

**Items:** 5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/review-route.test.sh::review surface`**

Generalise `review_surface` to `review_surface <codex true|false|absent> [agy true|false|absent]` (agy default `absent`), writing `$DR_AGY_SESSION_DIR/review-route-test.json` with `"review":<b>` (export `DR_AGY_SESSION_DIR="$TMP/agy-sessions"`). Every `codex:light` expectation becomes `panel:light`, `codex:heavy+judge-opus` becomes `panel:heavy+judge-opus`, `codex:plan` becomes `panel:plan`, `reason=codex-off` becomes `reason=reviewers-off`. Add:

```bash
review_surface false true
check "agy alone opens the light panel" "$(route --task 1 | grep -o 'primary=[^ ]*')" "primary=panel:light"
check "agy alone opens the heavy panel at risk 3" "$(route --task 8 | grep -o 'primary=[^ ]*')" "primary=panel:heavy+judge-opus"
check "agy alone opens the plan panel" "$(rround "$TMP/round.md" 1 | grep -o 'primary=[^ ]*')" "primary=panel:plan"
review_surface false false
check "no surface routes to Claude as reviewers-off" "$(route --task 1 | grep -o 'reason=[^ ]*')" "reason=reviewers-off"
review_surface true
check "risk 2 keeps the light panel" "$(route --task 4 | grep -o 'primary=[^ ]*')" "primary=panel:light"
```

(fixture Task 4 is the risk-2 task, `risky`). In `transcript.test.mjs`, add a case: a session command `bash scripts/run-review-panel --kind task --tier light …` counts one review dispatch with seat `panel:light`, and a route with `primary=panel:light` fits it.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh; timeout 120 node --test evals/controller/tests/transcript.test.mjs`
Expected: FAIL — routes still print `codex:`, agy is not read.

- [ ] **Step 3: Implement**

1. `review-route`: a surface helper returns success when `executor_session_on codex review` or `executor_session_on agy review` does; the task chain and the plan round print C11's seats; `reason=reviewers-off` replaces `reason=codex-off`.
2. `transcript.mjs`: match `run-review-panel` with `--kind` beside `run-codex-review.sh`, reading `--tier` the same way (default heavy), seat `panel:<tier>`; the `fits` rule treats a `panel:` primary as it treats `codex:`. Keep counting `run-codex-task.sh` (old transcripts).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh && timeout 120 node --test evals/controller/tests/transcript.test.mjs`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-route plugins/dforge/tests/review-route.test.sh evals/controller/lib/transcript.mjs evals/controller/tests/transcript.test.mjs
git commit -m "feat(dforge): route reviews to the reviewer panel"
```

### Task 11: task-step runs the panel and reads External findings

**Files:**
- Modify: `plugins/dforge/scripts/task-step` (`do_review` `:843-950`, `do_group` `:1055-1068`, `parse_report` `:1124-1210`)
- Modify: `plugins/dforge/skills/subagent-driven-development/references/task-reviewer-prompt.md` (`:247-276`, `:292`)
- Test: `plugins/dforge/tests/task-step.test.sh` (plus the gate stubs in `task-step-base.test.sh:24-26`, `task-step-settle.test.sh:26-28`), `plugins/dforge/tests/seats.test.sh:133`, `plugins/dforge/tests/task-loop-steps.acceptance.test.sh:205-234`

**Interfaces:**
- Consumes: C10, C11.
- Produces: C12.

**Items:** 5

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/task-step.test.sh::review seats`**

Replace the light and heavy seat cases (`:334-376`) with:

```bash
step review docs/plan.md 1
check "a light review prints the panel seat" "$(grep -c '^seat: panel:light prompt: .*task-1-review-prompt.md fallback: ' <<<"$out")" "1"
check "a light review prints the panel command" "$(grep -c '^panel: .*run-review-panel --kind task --tier light .*--out-dir .*task-1-review-panel' <<<"$out")" "1"
check "a light panel's timeout covers both rows" "$(grep '^timeout:' <<<"$out")" "timeout: 2590000"
check "the reviewers' prompt is written" "$([ -s "$WS/task-1-review-panel-prompt.md" ] && echo yes || echo no)" "yes"
check "a light judge prompt keeps the Second Pass for two lists" "$(grep -c '^## Second Pass' "$WS/task-1-review-prompt.md")" "1"
step review docs/plan.md 7
check "a heavy review prints the heavy panel seat" "$(grep -c '^seat: panel:heavy+judge-opus prompt: .* then: dforge:judge-opus' <<<"$out")" "1"
check "a heavy panel's timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 5590000"
check "the Second Pass names each reviewer's file" "$(grep -c -e 'task-7-review-panel/codex.json' -e 'task-7-review-panel/agy.json' "$WS/task-7-review-prompt.md")" "2"
```

Task 7 is the fixture's risk-3 task; keep the existing heavy case's setup before `step review docs/plan.md 7` (its `step start docs/plan.md 7` and commit, `:362-372`), and `$WS` is the workspace variable those cases use. The verdict case at `:1441-1454` uses `## External findings`; add one asserting a report whose external section is still `## Codex findings` exits 5. Gate stubs in the three task-step suites print C8 lines. `seats.test.sh:133` expects `## External findings`; `task-loop-steps.acceptance.test.sh:205-234` expects the Second Pass on every panel review and none when the route is `reviewers-off`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 900 bash plugins/dforge/tests/task-step.test.sh start verdict`
Expected: FAIL — task-step prints `codex:` seats and a single Codex command.

- [ ] **Step 3: Implement**

1. `do_review`: read the seat from `review-route` (C11); write the judge prompt and `task-N-review-panel-prompt.md` (today's Codex prompt build, unchanged in content); keep the Second Pass on every `panel:` seat and fill `[EXTERNAL_REVIEW_FILES]` with `<ws>/task-N-review-panel/<id>.json`, one per `executors ranked` id; print C12's lines with `panel: bash <plugin>/scripts/run-review-panel --kind task --tier <t> --cwd <cwd> --out-dir <ws>/task-N-review-panel --prompt <panel prompt>`, timeout per C12 from both judge blocks. A `gate:` line prints on `reason=reviewers-off`, naming each family's gate reason. The session substitutes the Claude fallback when the panel prints `lists=0` (prose in Task 12).
2. `do_group`: a group keeps its Claude band judge whatever the route (`panel:*` → the fallback seat; `panel:heavy+judge-opus` → `judge-opus`).
3. `parse_report`: the external section is `## External findings`; the "not the report's last section" error names it.
4. `task-reviewer-prompt.md`: Second Pass reads "the external reviewers' lists" from `[EXTERNAL_REVIEW_FILES]` (each may be absent), and the report's section is `## External findings`, tagging each finding with its origin `codex` or `agy`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 900 bash plugins/dforge/tests/task-step.test.sh && timeout 600 bash plugins/dforge/tests/task-step-base.test.sh && timeout 600 bash plugins/dforge/tests/task-step-settle.test.sh && timeout 300 bash plugins/dforge/tests/seats.test.sh && timeout 600 bash plugins/dforge/tests/task-loop-steps.acceptance.test.sh`
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "feat(dforge): run the panel from task-step"
```

### Task 12: References describe external review

**Files:**
- Create: `plugins/dforge/reference/external-review.md` (from `reference/executor-lane.md` §"Codex task review seats" `:476-556`, §"Final-review Codex round" `:557-622`, the `FALLBACK` row `:638`, §"The executor registry" `:641-669`, the codex review, gate and quota bullets `:670-690`, widened to the panel and agy)
- Delete: `plugins/dforge/reference/executor-lane.md`
- Modify: `plugins/dforge/reference/delegated-task.md` (delete `:6-8`, `:26`, `:45-51`, `:70-72`, `:190`, `:203`, `:629-630`, `:645-646`, `:776-800`, `:890-898`; rewrite `:27`, `:295-339`, `:487-526`, `:569`, `:685`, `:764-772`), `plugins/dforge/reference/final-review.md` (`:51`, `:59`, `:150`, `:294-335`, `:421`), `plugins/dforge/reference/native-codex.md:143`, `plugins/dforge/reference/session-budget.md:63`, `plugins/dforge/reference/ladder.md` (links), `plugins/dforge/reference/executors/*.json` and `plugins/dforge/tests/fixtures/executors/codex.json` (`reference` → `reference/external-review.md`; the fixture stays byte-identical to the shipped entry)
- Test: `plugins/dforge/tests/review-route.test.sh:702-712`, `plugins/dforge/tests/inline-mode.test.sh:51-52` (expects `external-review.md`), `plugins/dforge/tests/inline-only.acceptance.test.sh:183-184` and `plugins/dforge/tests/inline-only-execution.acceptance.test.sh:426-427` (their `HANDBACK to inline` greps go with the lane; delete those checks)

**Interfaces:**
- Consumes: C5, C10, C11, C12.
- Produces: C14.

**Items:** 3, 5

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Extend the test `plugins/dforge/tests/review-route.test.sh::references`**

The case at `:702-712` requires `reference/external-review.md` to exist and `reference/executor-lane.md` not to:

```bash
check "the external review reference exists" "$([ -f "$P/reference/external-review.md" ] && echo yes || echo no)" "yes"
check "the executor lane reference is gone" "$([ -f "$P/reference/executor-lane.md" ] && echo yes || echo no)" "no"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh`
Expected: FAIL — `external-review.md` does not exist.

- [ ] **Step 3: Implement**

Write `external-review.md`: the panel (C10) with its tiers (spec table), the `lists=0` substitution to the Claude seat said aloud with each runner's reason, how lists are consumed (no list, light one, light two with the band judge, heavy with `judge-opus`, whose verdict and scores count, plan round 1 with the lowest score per criterion deciding and every seat named on the `**Plan review:**` line), the final-review external round at depth full only with one list per reviewer and the dedupe judge whenever two or more lists carry findings, tagging origins as a `+`-joined set of `claude`, `codex`, `agy` (replacing `both`), the expected Opus-quota steady state and its ledger text `agy claude-opus-5-5 off (quota until <time>)`, the ledger seat clause (`seat codex gpt-6.1-sol/xhigh+agy gemini-4-argon/high+judge-sonnet-high`), the registry (C6), the gates (C8) and the quota rules. Move every link from `executor-lane.md` to it (`git grep -n executor-lane.md -- plugins/dforge ':!plugins/dforge/docs'`), rewrite the listed `delegated-task.md` and `final-review.md` passages to the panel and delete the executor ones; in `delegated-task.md`'s recovery section state the mid-lane rule (a task whose last ledger line names an executor with no complete line: `git status`, show the leftovers, keep or discard before implementing; leftover run records under the git directory are inert).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/review-route.test.sh && timeout 60 node scripts/validate-repository.mjs && timeout 300 bash plugins/dforge/tests/executors.test.sh && timeout 600 bash plugins/dforge/tests/inline-mode.test.sh && timeout 600 bash plugins/dforge/tests/inline-only.acceptance.test.sh && timeout 600 bash plugins/dforge/tests/inline-only-execution.acceptance.test.sh`
Then the Integration check (tasks 10-12 checkpoint).
Expected: PASS, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge
git commit -m "docs(dforge): describe the reviewer panel"
```

### Task 13: Skills drop the executor lane

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (`:215-217`, `:350-352`), `references/execution-line.md` (`:9-16`, `:21-23`, `:35-36`), `references/assignment-procedure.md` (`:12`, `:33-39`, `:45-46`, `:68-71`, `:80-82`), `references/assigning-implementers.md` (`:34-58`, `:91-93`), `references/auto-run-plan.md:15`, `references/lint-and-review.md` (`:17-22`, `:33-57`, `:84-90`), `references/plan-reviewer-prompt.md` (`:80-81`, `:98-136`)
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (`:3`, `:98`, `:104-111`, `:204`, `:222-226`, `:268-269`), `references/setup.md:95-99`, `references/ruling-seat.md` (`:6`, `:24-30`, `:49-50`, `:63`, `:68`), `references/recovery.md` (`:15-17`, `:24`)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (`:31-38`, `:180`, `:235`) and `references/` (`batching.md:10`, `escalation.md:23-27`, `ledger.md` `:7`, `:43`, `:50-52`, `:79-82`, `:132`, `process-graph.md` `:9`, `:32`, `:37-38`, `:64-66`, `ruling-prompt.md:122`, `ruling-seat.md` `:17`, `:34-36`, `example-workflow.md:47`)
- Modify: `plugins/dforge/skills/handoff/SKILL.md:72-76`

**Interfaces:**
- Consumes: C11, C12, C14.
- Produces: none.

**Items:** 1, 2, 5

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 0 = 4

- [ ] **Step 1: No new test, because the edited lines are skill prose no script reads; `node scripts/validate-repository.mjs` already catches a broken link or `dforge:` name, and Task 14's lane-name guard catches a surviving lane name**

- [ ] **Step 2: Run the existing checks before editing**

Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: PASS (baseline).

- [ ] **Step 3: Implement**

Delete every executor passage listed (executor offer and lane gate, `**Executor:**` line rules, delegated tasks, thread ids, `thread pending`, `lane-breaker`, `executor-empty-diff`). Rewrite the review passages: plan round 1 runs `run-review-panel --kind plan` as a background Bash call with `timeout` 5590000 ms and reads every list; `panel:plan` / `reviewers-off` replace `codex:plan` / `codex-off`; a task review runs the `panel:` command `task-step` prints. `recovery.md` states the mid-lane rule (as Task 12's `delegated-task.md`).

- [ ] **Step 4: Run the checks**

Run: `timeout 60 node scripts/validate-repository.mjs && timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge/skills
git commit -m "docs(dforge): drop the executor lane from skills"
```

### Task 14: Release surface and the lane-name guard

**Files:**
- Create: `plugins/dforge/tests/reviewer-only.acceptance.test.sh`
- Modify: `plugins/dforge/README.md` (sections `:52-425` at `:142`, `:198`, `:224`, `:280-317`; Requirements `:426`; the "Migrating to 4.11" section `:1038-1046`; Reference `:1295-1337`; add "Migrating to 5.0")
- Modify: `README.md:120`, `SECURITY.md:23-24`, `.claude-plugin/marketplace.json` (dforge description `:14`, keywords `:23-24`), `plugins/dforge/.claude-plugin/plugin.json` and `plugins/dforge/.codex-plugin/plugin.json` (descriptions, `interface.shortDescription`, keywords `codex`, `external-executors`; never the version line)
- Modify: `scripts/test-shards.mjs` (weight for the new suite)

**Interfaces:**
- Consumes: everything above.
- Produces: A10's guard.

**Items:** 1, 2, 3, 4, 5, 6, 7

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# The executor lane is gone: no shipped file names its scripts, settings or
# reference, and the README tells an upgrading user what moved.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names='run-codex-task\.sh|run-agy-task\.sh|lane-breaker|plan-revise|codexLane|agyLane|executor-lane\.md'
hits=$(cd "$P" && grep -rlE "$names" scripts reference skills hooks config .claude-plugin .codex-plugin 2>/dev/null | sort | tr '\n' ' ')
check "no shipped file names a lane script, setting or reference" "$hits" ""
section=$(awk '/^## Migrating to 5\.0/ { f = 1; next } f && /^## / { exit } f' "$P/README.md")
for name in codexLane agyLane agyReview revising-plans plan-revise; do
  check "the 5.0 migration names $name" "$(grep -c -- "$name" <<<"$section" | awk '{ print ($1 > 0) ? "yes" : "no" }')" "yes"
done
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/reviewer-only.acceptance.test.sh`
Expected: FAIL — no "Migrating to 5.0" section; any lane name left in a shipped file is listed.

- [ ] **Step 3: Implement**

1. Fix every file the guard lists.
2. `plugins/dforge/README.md`: the feature sections, Requirements and Reference describe the reviewer panel and the two switches; the settings table already follows Task 8; the "Migrating to 4.11" section drops its `plan-revise` and `dforge:revising-plans` steps; add "Migrating to 5.0" naming the removed `codexLane` and `agyLane`, the new `agyReview` switch (off by default; agy reviews only while `trust.review` is `pass`), the removed `revising-plans` skill and `plan-revise` (an old-format plan is fixed against `plan-lint` or re-planned), the obsolete `**Executor:**` line (a WARN), and the mid-lane rule.
3. Root `README.md`, `SECURITY.md`, the marketplace entry and both plugin manifests describe Codex and agy as reviewers; drop the `external-executors` keyword.
4. `scripts/test-shards.mjs`: `'reviewer-only.acceptance.test.sh': 5`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/reviewer-only.acceptance.test.sh && timeout 60 node scripts/release.mjs --dry-run`
Expected: PASS, 0 failed; the dry run prints `release dforge 4.17.1 -> 5.0.0` (A18). Then the Integration check.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dforge README.md SECURITY.md .claude-plugin/marketplace.json scripts/test-shards.mjs
git commit -m "docs(dforge): document the reviewer-only release"
```
