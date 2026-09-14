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

# The five output sections, in order.
sections=$(grep -oE '^- \*\*(Repos|In flight|Not started|Owner-only items|Next step)\*\*' "$SKILL" \
  | sed 's/^- \*\*//; s/\*\*$//' | tr '\n' '|')
check "status output sections in order" "$sections" "Repos|In flight|Not started|Owner-only items|Next step|"

present "status links project-state" "$SKILL" 'project-state.md'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
