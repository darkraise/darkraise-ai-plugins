#!/usr/bin/env bash
# Inline mode is a document, and the claims that make it work are structural:
# which ledger lines it writes and which files it links to.
# A model is not needed to check any of them, so they are checked here instead
# of in a review.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL_VIEW_DIR=$(mktemp -d)
trap 'rm -rf "$SKILL_VIEW_DIR"' EXIT
. "$HERE/skill-view.sh"
INLINE="$(skill_view executing-plans)"
FINAL="$P/reference/final-review.md"
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

for f in "$INLINE" "$FINAL"; do
  check "exists: $(basename "$(dirname "$f")")/$(basename "$f")" \
    "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# Links, and the files they point at.
check "the shared final review exists" \
  "$([ -f "$P/reference/final-review.md" ] && echo yes || echo no)" "yes"
check "the ruling prompt exists" \
  "$([ -f "$P/reference/prompts/ruling-prompt.md" ] && echo yes || echo no)" "yes"
check "the code reviewer reference exists" \
  "$([ -f "$P/skills/requesting-code-review/references/code-reviewer.md" ] && echo yes || echo no)" "yes"
check "the external review reference exists" \
  "$([ -f "$P/reference/external-review.md" ] && echo yes || echo no)" "yes"
check "the re-review prompt exists" \
  "$([ -f "$P/reference/prompts/re-review-prompt.md" ] && echo yes || echo no)" "yes"

# The ledger grammar.
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean' 'Review depth: <light|standard|full> (<reason>)' 'Acceptance QA: skipped (depth light)'; do
  present "inline ledger has: $line" "$INLINE" "$line"
done
for line in 'Review depth: <light|standard|full> (<reason>)' 'Acceptance QA: skipped (depth light)'; do
  check "executing-plans: the ledger grammar block holds the line $line" "$(grep -Fxc -- "$line" "$INLINE")" "1"
done

# --- the delegated loop ---
DT="$P/reference/delegated-task.md"
check "exists: reference/delegated-task.md" "$([ -f "$DT" ] && echo yes || echo no)" "yes"
NC="$P/reference/native-codex.md"
check "exists: reference/native-codex.md" "$([ -f "$NC" ] && echo yes || echo no)" "yes"
# validate-repository.mjs checks links only under skills/, so this suite pins
# the reference file's links.
for link in $(grep -oE '\]\([^)#]+\.md' "$DT" | sed 's/^](//' | sort -u); do
  check "delegated loop link resolves: $link" "$([ -f "$P/reference/$link" ] && echo yes || echo no)" "yes"
done

# --- the review marker and heavy list, computed by task-brief ---
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
brief "$DTMP/plan.md" 3 "$DTMP/b3.md"
check "a split task with a risk-3 part carries the review marker" "$(sed -n 2p "$DTMP/b3.md")" "**Review:** per-task — risk 3"
brief --header "$DTMP/plan.md" "$DTMP/h.md"
check "the header lists the heavy tasks with their scores" "$(tail -n 1 "$DTMP/h.md")" "**Heavy:** Task 2 (total 5, risk 2), Task 3 (total 4, risk 3)"

rm -rf "$DTMP"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
