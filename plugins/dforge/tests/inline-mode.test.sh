#!/usr/bin/env bash
# Inline mode is a document, and the claims that make it work are structural:
# which ledger lines it shares with subagent mode and which files it links to.
# A model is not needed to check any of them, so they are checked here instead
# of in a review.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL_VIEW_DIR=$(mktemp -d)
trap 'rm -rf "$SKILL_VIEW_DIR"' EXIT
. "$HERE/skill-view.sh"
INLINE="$(skill_view executing-plans)"
SDD="$P/skills/subagent-driven-development/SKILL.md"
FINAL="$P/reference/final-review.md"
. "$HERE/fixtures/sdd-text.sh"
# task-brief prints the budget line, which measures a Codex rollout and appends
# an observation row. This suite runs against the real HOME, so send the rollout
# search somewhere that does not exist: on a Codex host the live rollout is the
# newest file, and every brief below would otherwise append a junk row to the
# developer's own budget log.
export CODEX_HOME="$HERE/no-such-codex-home"
# The budget lines asserted here are the defaults'; the suite keeps the real
# home, so the settings in it are kept out by name.
export DFORGE_NO_SETTINGS=1
# Run inside an auto run's session, a brief would bind to that run.
unset CLAUDE_CODE_SESSION_ID AR_SESSION

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

for f in "$INLINE" "$SDD" "$FINAL"; do
  check "exists: $(basename "$(dirname "$f")")/$(basename "$f")" \
    "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# Links, and the files they point at.
check "the shared final review exists" \
  "$([ -f "$P/reference/final-review.md" ] && echo yes || echo no)" "yes"
check "the ruling prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/ruling-prompt.md" ] && echo yes || echo no)" "yes"
check "the code reviewer reference exists" \
  "$([ -f "$P/skills/requesting-code-review/references/code-reviewer.md" ] && echo yes || echo no)" "yes"
check "the external executor reference exists" \
  "$([ -f "$P/reference/executor-lane.md" ] && echo yes || echo no)" "yes"
check "the re-review prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/re-review-prompt.md" ] && echo yes || echo no)" "yes"

# The escalation clause both skills key on.
present "an owner request switches through the ledger line" "$INLINE" '`Task <N>: escalated inline -> subagent — owner request`'
present "subagent mode reads the escalation line" "$SDD" "escalated inline -> subagent"
ESC="$P/skills/subagent-driven-development/references/escalation.md"
present "an unavailable substitute ends in BLOCKED, not a loop" "$ESC" '`Task <N>: BLOCKED — no available implementer — <the models found unavailable>`'

# One ledger grammar for both modes.
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean' 'Review depth: <light|standard|full> (<reason>)' 'Acceptance QA: skipped (depth light)'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD_LEDGER" "$line"
done
for f in "$INLINE" "$SDD_LEDGER"; do
  s=$(basename "$(dirname "$f")")/$(basename "$f")
  for line in 'Review depth: <light|standard|full> (<reason>)' 'Acceptance QA: skipped (depth light)'; do
    check "$s: the ledger grammar block holds the line $line" "$(grep -Fxc -- "$line" "$f")" "1"
  done
done

# --- the delegated loop: one copy, shared by both execution skills ---
DT="$P/reference/delegated-task.md"
check "exists: reference/delegated-task.md" "$([ -f "$DT" ] && echo yes || echo no)" "yes"
NC="$P/reference/native-codex.md"
check "exists: reference/native-codex.md" "$([ -f "$NC" ] && echo yes || echo no)" "yes"
# validate-repository.mjs checks links only under skills/, so this suite pins
# the reference file's links.
for link in $(grep -oE '\]\([^)#]+\.md' "$DT" | sed 's/^](//' | sort -u); do
  check "delegated loop link resolves: $link" "$([ -f "$P/reference/$link" ] && echo yes || echo no)" "yes"
done

# --- the Dispatch line: mixed mode's delegation, computed by task-brief ---
DTMP=$(mktemp -d)
sed 's/^|//' > "$DTMP/plan.md" <<'EOF'
|# Mixed
|
|**Execution:** inline — `claude --model opus --effort high` — x
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: heavy
|
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 3: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF
brief() { bash "$P/scripts/task-brief" "$@" >/dev/null 2>&1; }
brief "$DTMP/plan.md" 1 "$DTMP/b1.md"
check "a light task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/b1.md")" "0"
brief "$DTMP/plan.md" 2 "$DTMP/b2.md"
check "a heavy task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/b2.md")" "0"
brief "$DTMP/plan.md" 3 "$DTMP/b3.md"
check "a split task with a risk-3 part carries the review marker" "$(sed -n 2p "$DTMP/b3.md")" "**Review:** per-task — risk 3"
brief --header "$DTMP/plan.md" "$DTMP/h.md"
check "the header lists the heavy tasks with their scores" "$(tail -n 1 "$DTMP/h.md")" "**Heavy:** Task 2 (total 5, risk 2), Task 3 (total 4, risk 3)"
check "a header with no executor task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/h.md")" "0"
sed 's/^\*\*Evaluation:\*\* files 1 - spec 1 - coupling 1 - risk 2 = 5$/**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4/; s/risk 3 = 4$/risk 0 = 1/' "$DTMP/plan.md" > "$DTMP/light.md"
brief --header "$DTMP/light.md" "$DTMP/hl.md"
check "a lone total-4 task in three is not delegated" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/hl.md")" "0"
sed 's/inline — `claude --model opus --effort high`/subagent — `claude --model sonnet --effort high`/' "$DTMP/plan.md" > "$DTMP/sub.md"
brief "$DTMP/sub.md" 2 "$DTMP/s2.md"
check "a subagent plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/s2.md")" "0"
grep -v '^\*\*Execution:\*\*' "$DTMP/plan.md" > "$DTMP/old.md"
brief "$DTMP/old.md" 2 "$DTMP/o2.md"
check "a plan with no Execution line has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/o2.md")" "0"
{ printf 'Host: codex\n\n'; cat "$DTMP/plan.md"; } > "$DTMP/cdx.md"
brief "$DTMP/cdx.md" 2 "$DTMP/c2.md"
check "a Codex-host plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/c2.md")" "0"
four_plan() { # four_plan <file> <total ...> — an inline plan, one task per total (1 or 4)
  local f=$1 i=0 t ev; shift
  printf '# Four\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n' > "$f"
  for t in "$@"; do
    i=$((i + 1))
    if [ "$t" -eq 4 ]; then ev='files 0 - spec 1 - coupling 1 - risk 2 = 4'; else ev='files 0 - spec 0 - coupling 1 - risk 0 = 1'; fi
    printf '\n### Task %s: t\n\n**Evaluation:** %s\n' "$i" "$ev" >> "$f"
  done
}
four_plan "$DTMP/one4.md" 1 4 1 1 1 1
brief "$DTMP/one4.md" 2 "$DTMP/f2.md"
check "a total-4 task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/f2.md")" "0"
brief --header "$DTMP/one4.md" "$DTMP/fh.md"
check "a total-4 task leaves no header Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/fh.md")" "0"

# --- the executor marker in the Dispatch line -------------------------------
sed 's/^|//' > "$DTMP/offload.md" <<'EOF'
|# Offload Fixture
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. offloaded
|2. plain
|
|### Task 1: offloaded
|
|**Implementer:** dforge:impl-sonnet-medium
|**Executor:** codex gpt-6.1-sol / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 2: plain
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
EOF

brief --header "$DTMP/offload.md" "$DTMP/oh.md"
check "the header marks an offloaded task" \
  "$(grep -c 'Task 1 (executor)' "$DTMP/oh.md")" "1"
check "the header does not mark a plain task" \
  "$(grep -c 'Task 2' "$DTMP/oh.md")" "0"

brief "$DTMP/offload.md" 1 "$DTMP/ob1.md"
check "an offloaded brief is marked delegated" \
  "$(sed -n 2p "$DTMP/ob1.md")" "**Dispatch:** delegated — total 2, risk 0"
brief "$DTMP/offload.md" 2 "$DTMP/ob2.md"
check "a self-implemented brief carries no Dispatch line" \
  "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/ob2.md")" "0"

rm -rf "$DTMP"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
