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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
