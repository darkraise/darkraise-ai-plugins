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
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
DT="$P/reference/delegated-task.md"
check "re-review: no model placeholder" "$(grep -c '\[MODEL\]' "$RRP")" "0"
names "re-review: the diff file is required" "$RRP" '`[DIFF_FILE]` — REQUIRED'

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
for t in "$TRP" "$RRP" "$GRP"; do
  n=$(basename "$t" .md)
  names "$n: names the report file" "$t" 'Write your full report to [REPORT_FILE] and write nothing else'
  check "$n: the report opens with the Verdict section" "$(grep -qE '^ *## Verdict$' "$t" 2>/dev/null && echo yes || echo no)" "yes"
  names "$n: the report file is a placeholder" "$t" '`[REPORT_FILE]` — REQUIRED'
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
names "re-review: the round verdict key" "$RRP" 'fix round: addressed | open'
names "re-review: the open count key" "$RRP" 'open: <k>'
names "group reviewer: the per-task finding grammar" "$GRP" '- [Critical|Important|Minor] (Task <N>) <file>:<line> — <one-liner>'
names "group reviewer: per-task verdict keys" "$GRP" 'Task <N> spec: pass | fail | cannot-verify'
names "group reviewer: per-task scores" "$GRP" 'Task <N> scores: spec <1-20> / scope <1-20> / verification <1-20> / quality <1-20>'

# The plan-review and critic seats follow the same report contract.
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
CP="$P/skills/brainstorming/references/architecture-critic-prompt.md"
AR="$P/reference/auto-run.md"
count_of() { grep -cF -- "$2" "$1" 2>/dev/null; } # count_of <file> <text> - lines holding text
check "plan reviewer: both templates name the report file" "$(count_of "$PRP" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
names "critic: names the report file" "$CP" 'Write your full report to [REPORT_FILE] and write nothing else'

# The final review's seats and the standalone verifiers follow the same report
# contract.
CM="$P/skills/closing-a-milestone/SKILL.md"
DJ="$P/skills/distilling-docs/references/distil-judge.md"
SJ="$P/skills/test-simplifier/references/simplify-judge.md"
WT="$P/skills/ui-ux/references/walkthrough.md"
SA="$P/skills/selecting-approaches/SKILL.md"
names "code reviewer: names the report file" "$CR" 'Write your full report to [REPORT_FILE] and write nothing else'
names "distil judge: names the report file" "$DJ" 'Write your full report to [REPORT_FILE] and write nothing else'
check "simplify judge: both prompts name the report file" "$(count_of "$SJ" 'Write your full report to [REPORT_FILE] and write nothing else')" "2"
names "walkthrough judge: names the report file" "$WT" 'Write your full report to [REPORT_FILE] and write nothing else'

# The cockpit's write guard lets a judge seat write only a path ending
# `-report.md`, so every report path a judge dispatch names must end that way.
# bad_report_paths FILE... - "FAIL <file>: <path>" per backticked path that does not
bad_report_paths() {
  local f t
  for f in "$@"; do
    grep -iE 'REPORT_FILE|report to|report file' "$f" | grep -oE '`[^`]*`' | tr -d '`' \
      | grep -E '/.*\.md$' | grep -vE -- '-report\.md$' \
      | while IFS= read -r t; do printf 'FAIL %s: %s\n' "${f#"$P"/}" "$t"; done
  done
}
JUDGE_TEMPLATES=(
  "$P/skills/writing-plans/references/lint-and-review.md" "$PRP"
  "$FR" "$DT" "$AR" "$WT"
  "$RRP" "$GRP" "$RULP" "$P/skills/subagent-driven-development/references/ruling-seat.md" "$TRP"
  "$P/skills/executing-plans/references/ruling-seat.md"
  "$CR" "$RCR" "$DJ" "$SJ" "$CM" "$SA"
  "$P/skills/brainstorming/references/architecture-critic.md" "$CP"
)
check "judge templates: every report path ends -report.md" "$(bad_report_paths "${JUDGE_TEMPLATES[@]}")" ""
sed 's|lens-<id>-report\.md|lens-<id>.md|' "$FR" > "$TMP/final-review.md"
check "judge templates: the sweep flags a report path the guard refuses" \
  "$(bad_report_paths "$TMP/final-review.md" | grep -c '^FAIL .*: <workspace>/lens-<id>\.md$')" "1"
names "walkthrough judge: the report file lies under .dforge" "$WT" '`<checkout>/.dforge/ui-proof-<report name>-report.md`'
lacks "requesting review: the example report file is absolute" "$RCR" 'REPORT_FILE: .dforge/'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
