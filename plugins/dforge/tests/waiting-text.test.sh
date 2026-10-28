#!/usr/bin/env bash
# A Claude Code session waits for background work by ending its turn, and only
# Codex waits in bounded wait_agent stretches. The skill text must not send a
# Claude Code session back to Monitor or sleep polling, and must keep Codex's
# stretches where they are.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SDD="$P/skills/subagent-driven-development/SKILL.md"
DT="$P/reference/delegated-task.md"
CODEX="$P/skills/using-dforge/references/codex-tools.md"
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}

# polling FILE - one "line: text" per line that names a Monitor, a sleep or an
# until-loop without forbidding it
polling() {
  grep -n -i -E 'monitor|sleep|until-loop' "$1" \
    | grep -vF 'Never wait with `Monitor`, `sleep` or a polling loop.' || true
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILL_VIEW_DIR="$TMP/views"
mkdir "$SKILL_VIEW_DIR"
. "$HERE/skill-view.sh"
INLINE="$(skill_view executing-plans)"

cat > "$TMP/old-wait.md" <<'FIXTURE'
On Claude Code a bounded stretch is a `Monitor` with an until-loop, never a
background `sleep`: a sleep is one more launch that has not reported back.
FIXTURE
check "a Monitor wait is caught" "$(polling "$TMP/old-wait.md" | cut -d: -f1 | tr '\n' ' ')" "1 2 "

cat > "$TMP/new-wait.md" <<'FIXTURE'
Never wait with `Monitor`, `sleep` or a polling loop.
FIXTURE
check "the prohibition is not caught" "$(polling "$TMP/new-wait.md")" ""

check "subagent-driven-development prescribes no Monitor or sleep wait" "$(polling <(sdd_text))" ""
names "a Claude Code session ends the turn when only waiting remains" "$SDD" \
  'arrive on their own. When only waiting remains, end the turn: each completion'
names "the prohibition is stated" "$SDD" 'Never wait with `Monitor`, `sleep` or a polling loop.'
names "a notification turn starts with in-flight" "$SDD" 'On a turn that a notification started, run `scripts/in-flight` before'
lacks "the bounded Monitor stretch is gone" <(sdd_text) 'a bounded stretch is a `Monitor`'
lacks "the stretch advice is gone" <(sdd_text) 'wait in bounded stretches (five to ten'
names "Codex keeps its stretches in the skill" "$SDD" 'On Codex, `wait_agent` covers the idle window instead, in bounded stretches,'
lacks "the delegated loop no longer says wait in bounded stretches" "$DT" 'wait in bounded stretches'
names "the delegated loop points at the waiting rule" "$DT" \
  'subagents says (on Claude Code, end the turn; on Codex, bounded `wait_agent`'

names "codex-tools keeps the bounded wait_agent stretch" "$CODEX" 'bounded stretches: `wait_agent` with `timeout_ms` 300000-600000'
names "codex-tools keeps the five-minute floor" "$CODEX" 'Never stack polls shorter than five minutes'

names "the ruling route takes a comma-separated kind list" "$SDD_RULING_SEAT" '`<kind>` is then one comma-separated list, such as'
names "simple kinds route to judge-sonnet-high" "$SDD_RULING_SEAT" '`dforge:judge-sonnet-high` (`reason=simple-kind`) when every kind in the list'
names "the other kinds stay on judge-opus" "$SDD_RULING_SEAT" '`blocked-plan`, `final-residual` and `acceptance-ambiguous` always go to'
names "a mechanical check settles a cannot-verify item" "$SDD_RULING_SEAT" '`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`,'
names "a failed check is a fix-loop finding" "$SDD_RULING_SEAT" 'finding for the fix loop, not a cannot-verify item.'
names "inline mode routes the simple kinds" "$INLINE" '`dforge:judge-sonnet-high` when every kind is `cannot-verify` or'
names "inline mode settles by mechanical check" "$INLINE" '`Task <N>: Ruling: cannot-verify — settled by task-step check <name> — none`.'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
