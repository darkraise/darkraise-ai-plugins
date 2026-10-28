#!/usr/bin/env bash
# Every dforge seat is typed. A general-purpose prescription must name its
# model, or it inherits the session's, usually the most expensive. A
# prescription is a `Subagent (general-purpose):` template line, which needs a
# `model:` line before its block's closing fence, or a table row whose second
# cell (a Seats table's Agent column) is `general-purpose`, which needs a
# backticked model alias in the same row.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

# unmodelled FILE... - one "file:line" per general-purpose prescription with no model
unmodelled() {
  awk '
    FNR == 1 { if (open) print where; open = 0 }
    open && /^[ \t]+prompt:/ { inprompt = 1 }
    open && !inprompt && /^[ \t]+model:/ { open = 0 }
    open && /^```/ { print where; open = 0 }
    /Subagent \(general-purpose\):/ { open = 1; inprompt = 0; where = FILENAME ":" FNR; next }
    /^\|/ {
      n = split($0, cell, "|")
      agent = cell[3]; gsub(/^[ \t]+/, "", agent); gsub(/[ \t]+$/, "", agent)
      if (agent == "general-purpose" && $0 !~ /`(sonnet|opus|haiku|fable)`/) print FILENAME ":" FNR
    }
    END { if (open) print where }
  ' "$@"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# collect_md DIR... - fill the files array with the markdown files under each DIR
collect_md() {
  files=()
  local f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$@" -name '*.md' -print0 | LC_ALL=C sort -z)
}
collect_md "$P/skills" "$P/reference"
check "the prescription scan reads some files" "$([ "${#files[@]}" -gt 0 ] && echo yes || echo no)" "yes"
check "no dforge prescription leaves a general-purpose seat unmodelled" "$(unmodelled ${files[@]+"${files[@]}"})" ""

cat > "$TMP/bad-block.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Review"
  prompt: |
    Review it.
```
EOF
check "a template block with no model is caught" "$(unmodelled "$TMP/bad-block.md")" "$TMP/bad-block.md:2"

cat > "$TMP/bad-row.md" <<'EOF'
| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | None |
EOF
check "a Seats row with no model is caught" "$(unmodelled "$TMP/bad-row.md")" "$TMP/bad-row.md:3"

cat > "$TMP/good.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Probe"
  model: sonnet
  prompt: |
    Probe it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | `sonnet` |
EOF
check "a modelled block and row pass" "$(unmodelled "$TMP/good.md")" ""

cat > "$TMP/prompt-model.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Review"
  prompt: |
    Reply with
      model: sonnet
```
EOF
check "a model: line inside the prompt body does not model the block" "$(unmodelled "$TMP/prompt-model.md")" "$TMP/prompt-model.md:2"

mkdir -p "$TMP/with space"
cp "$TMP/bad-block.md" "$TMP/with space/bad.md"
collect_md "$TMP/with space"
check "a checkout path with a space is still scanned" "$(unmodelled ${files[@]+"${files[@]}"})" "$TMP/with space/bad.md:2"

RCR="$P/skills/requesting-code-review/SKILL.md"
CR="$P/skills/requesting-code-review/references/code-reviewer.md"
UD="$P/skills/using-dforge/SKILL.md"
names "requesting review: the judge seat" "$RCR" 'Dispatch `dforge:judge-opus` as `subagent_type`'
names "requesting review: the diff file comes first" "$RCR" 'git diff -U10 "$BASE_SHA..$HEAD_SHA"'
names "requesting review: the diff file is checked before dispatch" "$RCR" '[ -s "$DIFF_FILE" ] && ! git diff --quiet "$BASE_SHA..$HEAD_SHA"'
names "requesting review: the diff file needs a base" "$RCR" '[ -n "$BASE_SHA" ]'
names "requesting review: the state directory ignores itself" "$RCR" 'dforge_self_ignore "$STATE_DIR"'
check "requesting review: no general-purpose seat" "$(grep -c 'general-purpose' "$RCR")" "0"
names "code reviewer: the judge seat" "$CR" 'Subagent (dforge:judge-opus):'
check "code reviewer: no git fallback" "$(grep -c 'derive it yourself' "$CR")" "0"
names "code reviewer: the diff file is required" "$CR" '`[DIFF_FILE]` — REQUIRED'
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
DT="$P/reference/delegated-task.md"
names "re-review: the judge seat" "$RRP" 'Subagent (dforge:judge-sonnet-high; dforge:judge-opus for a subtle concurrency fix):'
check "re-review: no general-purpose seat" "$(grep -c 'general-purpose' "$RRP")" "0"
check "re-review: no model line" "$(grep -c '^  model:' "$RRP")" "0"
check "re-review: no model placeholder" "$(grep -c '\[MODEL\]' "$RRP")" "0"
check "re-review: no git fallback" "$(grep -c 'git diff' "$RRP")" "0"
names "re-review: the diff file is required" "$RRP" '`[DIFF_FILE]` — REQUIRED'
names "re-review: the read-only clause stays" "$RRP" 'Your review is read-only on this checkout.'
check "delegated loop: no general-purpose re-review row" "$(grep -c '^| Scoped re-review | general-purpose' "$DT")" "0"
names "delegated loop: the re-review row names the judge seats" "$DT" '| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |'
names "entry point: the Seats section" "$UD" '## Seats'
names "entry point: general-purpose takes a model" "$UD" '`general-purpose` takes an explicit `model`'
names "entry point: read-only checks on a judge" "$UD" 'Read-only checks (register rows, findings, a claim) go to `dforge:judge-sonnet-high`'

# Judge seats in the task loop write their full report to the file the prompt
# names and reply in at most ten lines. The report opens with a fixed
# `## Verdict` section and lists findings in one grammar, so task-step verdict
# can read it and the controller never has to.
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
RULP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
FR="$P/reference/final-review.md"
for t in "$TRP" "$RRP" "$GRP" "$RULP"; do
  n=$(basename "$t" .md)
  names "$n: names the report file" "$t" 'Write your full report to [REPORT_FILE] and write nothing else'
  names "$n: the reply is at most 10 lines" "$t" 'Then reply in at most 10 lines'
  check "$n: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$t" 2>/dev/null && echo yes || echo no)" "yes"
  names "$n: the report file is a placeholder" "$t" '`[REPORT_FILE]` — REQUIRED'
  lacks "$n: the final message is no longer the report" "$t" 'Your final message is the report itself'
  lacks "$n: the seat no longer says it cannot modify files" "$t" 'You cannot modify files'
done
for t in "$TRP" "$RRP"; do
  n=$(basename "$t" .md)
  names "$n: the finding grammar" "$t" '- [Critical|Important|Minor] <file>:<line> — <one-liner>'
  names "$n: the implementer's report has its own placeholder" "$t" '[IMPLEMENTER_REPORT_FILE]'
done
names "task reviewer: the spec verdict key" "$TRP" 'spec: pass | fail | cannot-verify'
names "task reviewer: the quality verdict key" "$TRP" 'quality: approved | changes'
names "task reviewer: the scores key" "$TRP" 'scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>'
names "task reviewer: the cannot-verify section" "$TRP" '## Cannot verify'
check "task reviewer: the Codex findings are a report section" "$(grep -qE '^ *## Codex findings$' "$TRP" && echo yes || echo no)" "yes"
lacks "task reviewer: no Verification Scores block" "$TRP" '### Verification Scores'
names "re-review: the round verdict key" "$RRP" 'fix round: addressed | open'
names "re-review: the open count key" "$RRP" 'open: <k>'
names "re-review: the per-finding verdicts" "$RRP" '## Finding verdicts'
names "group reviewer: the per-task finding grammar" "$GRP" '- [Critical|Important|Minor] (Task <N>) <file>:<line> — <one-liner>'
names "group reviewer: per-task verdict keys" "$GRP" 'Task <N> spec: pass | fail | cannot-verify'
names "group reviewer: per-task scores" "$GRP" 'Task <N> scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>'
names "ruling: the item verdict lines" "$RULP" 'Verdict: CONFIRMED-GAP | PARK | AMEND | REWORD | BLOCKED'
names "ruling: an AMEND names its entry" "$RULP" 'Amendment: A<k>'
names "ruling: entries are numbered in the report" "$RULP" '## A<k> — Task <N>'
names "ruling: a BLOCKED reply carries the decision" "$RULP" 'the decision a human must make'
names "ruling: the report file follows the items file" "$RULP" '`<workspace>/rulings-<point>-<task>-report.md`'
lacks "ruling: no unnumbered entry heading" "$RULP" '## A? — Task <N>'
names "final review: the fix wave's re-review names the fixer's report" "$FR" 'its `[IMPLEMENTER_REPORT_FILE]` being that file'
lacks "final review: the re-review's REPORT_FILE is not the fixer's" "$FR" 'its `[REPORT_FILE]` being that file'

# The plan-review, critic, spec-review and pre-execution ruling seats follow
# the same report contract: the full report in a file, a reply of at most ten
# lines, a fixed `## Verdict` section.
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
WP="$P/skills/writing-plans/SKILL.md"
CP="$P/skills/brainstorming/references/architecture-critic-prompt.md"
BS="$P/skills/brainstorming/SKILL.md"
AR="$P/reference/auto-run.md"
count_of() { grep -cF -- "$2" "$1" 2>/dev/null; } # count_of <file> <text> - lines holding text
check "plan reviewer: both templates name the report file" "$(count_of "$PRP" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
check "plan reviewer: both templates cap the reply" "$(count_of "$PRP" 'Then reply in at most 10 lines')" "2"
check "plan reviewer: both reports open with the Verdict section" "$(grep -cE '^ *## Verdict$' "$PRP")" "2"
check "plan reviewer: both carry the scores key" "$(count_of "$PRP" 'scores: executability <1-20> / coherence <1-20> / coverage <1-20> / assumptions <1-20>')" "2"
check "plan reviewer: both carry the finding grammar" "$(count_of "$PRP" '- [Critical|Important|Minor] <file>:<line> — <one-liner>')" "2"
check "plan reviewer: the prior findings section" "$(grep -cE '^ *## Prior findings$' "$PRP")" "1"
names "plan reviewer: the report file placeholder" "$PRP" '`[REPORT_FILE]` - REQUIRED: `<workspace>/plan-review-round-<r>.md`'
lacks "plan reviewer: no longer forbids modifying files" "$PRP" 'You cannot run commands, modify files, or dispatch subagents.'
check "plan reviewer: the seat writes only its report, and change 3 quotes that line" \
  "$(count_of "$PRP" 'You cannot run commands or dispatch subagents, and you write only the report file.')" "3"
lacks "writing-plans: the controller no longer saves the reply" "$WP" 'save its reply to'
lacks "writing-plans: nor saves each native reply" "$WP" 'saving each'
names "writing-plans: round 1 names the report file" "$P/skills/writing-plans/references/lint-and-review.md" '`[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`'
names "writing-plans: later rounds name the report file" "$P/skills/writing-plans/references/lint-and-review.md" '`[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`'
names "critic: names the report file" "$CP" 'Write your full report to [REPORT_FILE] and write nothing else'
names "critic: caps the reply" "$CP" 'Then reply in at most 10 lines'
check "critic: the report opens with the Verdict section" "$(grep -cE '^ *## Verdict$' "$CP")" "1"
names "critic: the counts key" "$CP" 'findings: <b> Blocker, <h> High, <m> Medium, <n> Nit'
names "critic: the finding grammar on its own scale" "$CP" '- [Blocker|High|Medium|Nit] <file>:<line> — <one-liner>'
names "critic: the report file" "$CP" '`<state>/critic-<spec name>-report.md`'
names "spec review: the report file" "$P/skills/brainstorming/references/architecture-critic.md" '`<state>/spec-review-<spec name>-<r>-report.md`'
names "spec review: the reply rule" "$P/skills/brainstorming/references/architecture-critic.md" 'write nothing else, and reply in at most 10 lines'
names "spec review: the open count decides a second round" "$P/skills/brainstorming/references/architecture-critic.md" 'open: <b> Blocker, <h> High'
lacks "spec review: a folded critic's findings are in the report" "$BS" 'so its reply carries the'
names "auto run: the spec review's report file" "$AR" '`<state>/spec-review-<spec name>-<r>-report.md`'
names "auto run: the pre-execution ruling's report file" "$AR" '`<state>/rulings-preexec-<k>-report.md`'
names "auto run: the Fable batch's report file" "$AR" '`<state>/rulings-fable-<k>-report.md`'
check "auto run: every seat it dispatches caps its reply" "$(count_of "$AR" 'write nothing else, and reply in at most 10 lines')" "3"

# The final review's seats and the standalone verifiers follow the same report
# contract.
MJ="$P/skills/closing-a-milestone/references/milestone-judge.md"
CM="$P/skills/closing-a-milestone/SKILL.md"
DJ="$P/skills/distilling-docs/references/distil-judge.md"
DD="$P/skills/distilling-docs/SKILL.md"
SJ="$P/skills/test-simplifier/references/simplify-judge.md"
WT="$P/skills/ui-ux/references/walkthrough.md"
SA="$P/skills/selecting-approaches/SKILL.md"
RM="$P/README.md"
names "code reviewer: names the report file" "$CR" 'Write your full report to [REPORT_FILE] and write nothing else'
names "code reviewer: caps the reply" "$CR" 'Then reply in at most 10 lines'
check "code reviewer: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$CR" && echo yes || echo no)" "yes"
names "code reviewer: the merge verdict key" "$CR" 'ready to merge: yes | no | with fixes'
names "code reviewer: the finding grammar" "$CR" '- [Critical|Important|Minor] <file>:<line> — <one-liner>'
names "code reviewer: the report file placeholder" "$CR" '`[REPORT_FILE]` — REQUIRED'
names "requesting review: the report file beside the diff" "$RCR" 'REPORT_FILE="$STATE_DIR/review-$(git rev-parse --short "$HEAD_SHA")-report.md"'
names "final review: the reviewer's report file" "$FR" '`[REPORT_FILE]` set to `<workspace>/final-review-report.md`'
names "final review: lens seats write their report" "$FR" 'each lens seat writes its report to `<workspace>/lens-<id>.md`'
names "final review: the lens finding grammar" "$FR" '- [Critical|Important|Minor] <file>:<line> — [lens:<id>] <one-liner>'
names "final review: the dedupe report file" "$FR" '`<workspace>/final-dedupe-report.md`'
check "final review: the lens and dedupe seats cap their reply" "$(count_of "$FR" 'write nothing else, and reply in at most 10 lines')" "2"
lacks "final review: the controller no longer saves lens replies" "$FR" 'save each reply to'
names "milestone judge: writes its report file" "$MJ" 'write nothing else'
names "milestone judge: caps the reply" "$MJ" 'reply in at most 10 lines'
check "milestone judge: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$MJ" && echo yes || echo no)" "yes"
names "closing a milestone: the report file" "$CM" '`<state>/milestone-M<n>-audit-report.md`'
names "distil judge: names the report file" "$DJ" 'Write your full report to [REPORT_FILE] and write nothing else'
names "distil judge: caps the reply" "$DJ" 'Then reply in at most 10 lines'
check "distil judge: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$DJ" && echo yes || echo no)" "yes"
names "distil judge: the per-source verdict line" "$DJ" '<source path>: CARRIED | MISSING | DISTORTED'
lacks "distilling: the judge's tools are stated as they are" "$DD" 'grants `Read, Grep, Glob, WebFetch` and'
check "simplify judge: both prompts name the report file" "$(count_of "$SJ" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
check "simplify judge: both prompts cap the reply" "$(count_of "$SJ" 'Then reply in at most 10 lines')" "2"
names "simplify judge: the ruling verdict key" "$SJ" 'verdict: KEPT | LOST | VIOLATED'
names "walkthrough judge: names the report file" "$WT" 'Write your full report to [REPORT_FILE] and write nothing else'
names "walkthrough judge: caps the reply" "$WT" 'Then reply in at most 10 lines'
names "walkthrough judge: the verdict key" "$WT" 'verdict: ship | fix [FINGERPRINT]'
lacks "walkthrough: the controller no longer saves the reply" "$WT" 'Save the reply verbatim'
check "approaches: the ranker and the advisor cap their reply" "$(count_of "$SA" 'write nothing else, and reply in at most 10 lines')" "2"
names "approaches: the ranking's report file" "$SA" '`<state>/approaches-<decision>-rank-report.md`'
lacks "README: the judges are no longer described as Write-free" "$RM" 'frontmatter omits `Edit`, `Write`, and `Agent`'
names "README: a judge writes only its report file" "$RM" 'a judge writes only its report file'
names "native Codex: a judge writes only its report file" "$P/reference/native-codex.md" 'no file writes except the one report file the prompt names'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
