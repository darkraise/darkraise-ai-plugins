#!/usr/bin/env bash
# project-status and the shared project-state reference are documents, and the
# claims that make them work are structural: which files they name, which order
# their recommendation rules appear in, and which scripts they must never call.
# A model is not needed to check any of them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STATE="$P/reference/project-state.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
check "exists: reference/project-state.md" \
  "$([ -f "$STATE" ] && echo yes || echo no)" "yes"

# The six project-state paths. A skill that names a different path than this
# reference document is naming a file no other skill writes.
for path in \
  'docs/superpowers/gates.md' \
  'docs/superpowers/plans/completed.md' \
  'docs/superpowers/distilled/constraints.md' \
  'docs/superpowers/distilled/gotchas.md' \
  'docs/superpowers/distilled/reference.md' \
  'docs/superpowers/distilled/rejected.md'; do
  present "project-state names $path" "$STATE" "$path"
done

# The precedence order is the whole point of the document: a skill that acts on
# the losing side of it has made an error, not a judgment call.
present "project-state states precedence" "$STATE" "## Precedence"
present "project-state ranks CLAUDE.md first" "$STATE" "anything your human partner says directly"
present "project-state ranks handoff above distilled" "$STATE" "yields to"
present "project-state says every file is optional" "$STATE" "Every one of these is optional"

SKILL="$P/skills/project-status/SKILL.md"
check "exists: skills/project-status/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

# The one script it may call, and the two it must not. Both forbidden names
# appear in the body explaining why, so assert the prohibition rather than the
# absence: sdd-workspace runs mkdir -p and rewrites a .gitignore, and next-step
# rewrites latest.md. This skill writes nothing.
present "status calls repo-audit" "$SKILL" 'scripts/repo-audit'
present "status forbids sdd-workspace" "$SKILL" 'never call `scripts/sdd-workspace`'
present "status forbids next-step" "$SKILL" 'never calls `scripts/next-step`'

# The plan discriminator. Most plans predate the Execution header, so keying on
# it would make the skill ignore them.
present "status uses the task-heading discriminator" "$SKILL" 'plan_tasks'
present "status rejects the Execution header" "$SKILL" 'Do **not** use the `**Execution:**` header as the discriminator'

# completed.md is the only completion signal, and it gates rules 4 and 5.
present "status names the completed index" "$SKILL" 'docs/superpowers/plans/completed.md'
present "status gates rules 4 and 5 on the index" "$SKILL" 'Rules 4 and 5 require'

# The recommendation table must stay ordered: two sessions on one repo reach
# the same step only if the rules are read in a fixed order.
rules=$(grep -oE '^\| [0-7] \|' "$SKILL" | grep -oE '[0-7]' | tr '\n' ' ')
check "status rules run 0 to 7 in order" "$rules" "0 1 2 3 4 5 6 7 "
present "status rule 0 reads the last line per task" "$SKILL" "A task's **last** ledger line is"
present "status routes to resume-execution" "$SKILL" 'dr-superpowers:resume-execution'

# The six output sections, in order.
sections=$(grep -oE '^- \*\*(Repos|In flight|Not started|Owner-only items|Open items|Next step)\*\*' "$SKILL" \
  | sed 's/^- \*\*//; s/\*\*$//' | tr '\n' '|')
check "status output sections in order" "$sections" "Repos|In flight|Not started|Owner-only items|Open items|Next step|"

present "status links project-state" "$SKILL" 'project-state.md'

# A constraint that outranks a spec must load where it can still bind. These
# two skills are the pick-up seat and the design seat.
RESUME="$P/skills/resume-execution/SKILL.md"
BRAIN="$P/skills/brainstorming/SKILL.md"
present "resume loads distilled constraints" "$RESUME" 'distilled/constraints.md'
present "resume loads distilled gotchas" "$RESUME" 'distilled/gotchas.md'
present "resume says constraints yield to handoff" "$RESUME" 'yield to'
present "brainstorming loads distilled constraints" "$BRAIN" 'distilled/constraints.md'
present "brainstorming loads rejected approaches" "$BRAIN" 'distilled/rejected.md'

# An approved spec's owner decision may land in constraints.md by hand; the
# writer rule must say so, or the first such entry breaks it. The last five
# checks read this repository's own docs tree, not a plugin file.
present "project-state allows an owner-decision entry" "$STATE" "a human may add an entry that an approved spec's owner decisions"
present "project-state names writing-plans as a constraints reader" "$STATE" '`constraints.md` also dr-superpowers:writing-plans'
CONSTRAINTS="$P/../../docs/superpowers/distilled/constraints.md"
check "exists: docs/superpowers/distilled/constraints.md" \
  "$([ -f "$CONSTRAINTS" ] && echo yes || echo no)" "yes"
present "the Codex lane is declared on" "$CONSTRAINTS" "### The Codex executor lane is on"
present "the lane entry cites the review-routing spec" "$CONSTRAINTS" "Source: docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md@"
present "the lane entry records who set it" "$CONSTRAINTS" "Set by: owner"
present "the lane entry waits for the session gate" "$CONSTRAINTS" 'When `scripts/codex-gate` reports `lane=true`'

# --- item registers ---
# Every needle below sits on one source line in the skill: these assert with
# grep -F, and a phrase the file wraps can never match.
SKILL="$P/skills/project-status/SKILL.md"
present "status: names the registers directory" "$SKILL" "docs/superpowers/registers/"
present "status: completed.md is no longer the only completion signal" "$SKILL" \
  "not whether the work is finished"
present "status: a register can veto done" "$SKILL" \
  "Never report work complete while a covering register has an unresolved row"
present "status: the report has an open-items section" "$SKILL" "**Open items**"
present "status: verify rows are the owner's" "$SKILL" "awaiting your check"
present "status: six sections now" "$SKILL" "Six sections, in this order"
present "state: registers are listed" "$STATE" "docs/superpowers/registers/"
if grep -qF "is the only completion signal" "$SKILL"; then
  printf 'FAIL - status: the old single-source rule is gone\n'; fail=$((fail + 1))
else
  printf 'ok   - status: the old single-source rule is gone\n'; pass=$((pass + 1))
fi

# --- finishing resolves register rows ---
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
present "finishing: the register gates the completion line" "$FIN" \
  "Only when every covering register is fully resolved"
present "finishing: an unresolved register changes the line" "$FIN" \
  "After integration: <n> register rows are still open"
present "finishing: rows are resolved through the script" "$FIN" "scripts/register set"
present "finishing: discovered work becomes a row" "$FIN" "scripts/register add"
present "finishing: verify is the owner's state" "$FIN" \
  "a check only your human partner can perform"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
