#!/usr/bin/env bash
# This skill deletes files. The checks below pin the three conditions that make
# a deletion recoverable, the judge gate that must clear first, and the commit
# shape the recovery story depends on.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/distilling-docs/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

check "exists: skills/distilling-docs/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

# The four output files.
for f in constraints gotchas reference rejected; do
  present "names distilled/$f.md" "$SKILL" "distilled/$f.md"
done
present "every entry carries Source" "$SKILL" 'Source:'

# The three eligibility conditions. Each one closes a path by which a fact
# could be destroyed with no way back.
present "eligible paths are notes and findings" "$SKILL" 'docs/superpowers/findings/'
present "eligible is markdown only" "$SKILL" 'Markdown files (`*.md`) under'
present "condition: tracked" "$SKILL" 'git ls-files --error-unmatch'
present "condition: clean" "$SKILL" 'git status --porcelain'
present "condition: unreferenced" "$SKILL" 'git grep'
present "ancestor directories count as references" "$SKILL" 'nor any **ancestor**'

# Never-eligible. A judge cannot enumerate facts in a PNG, so CARRIED is
# unreachable for one by construction.
present "specs and plans are never deleted" "$SKILL" 'Never deleted'
present "hand-written research is never deleted" "$SKILL" 'docs/reverse-engineering/'
present "non-markdown under notes is never eligible" "$SKILL" 'never eligible'

# The judge gate.
present "dispatches judge-fable" "$SKILL" 'dr-superpowers:judge-fable'
present "names judge-opus as the substitute" "$SKILL" 'dr-superpowers:judge-opus'
for v in CARRIED MISSING DISTORTED; do
  present "verdict $v" "$SKILL" "$v"
done
present "judge enumerates before mapping" "$SKILL" 'enumerate every fact in each source as a numbered list first'
present "commit before judging" "$SKILL" 'before the judge runs'
present "judge reads the working tree, not the commit" "$SKILL" 'no Bash'

# The commit shape.
present "exactly one removal commit" "$SKILL" 'exactly one removal commit'
present "never squashed" "$SKILL" 'never squashed on integration'
present "waves are bounded" "$SKILL" 'never the whole tree'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
