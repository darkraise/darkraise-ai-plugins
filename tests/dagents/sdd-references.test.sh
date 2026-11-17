#!/usr/bin/env bash
# subagent-driven-development keeps SKILL.md small by moving what one step
# reads into references/. A moved reference must exist and be linked from
# SKILL.md by a "Read ... before you ..." line, so a session that lost the tail
# of the skill after compaction still reaches it, and every relative link in
# the skill and its moved references must resolve.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# broken_links <file> - every relative link target in FILE that does not exist
broken_links() {
  local dir target
  dir=$(dirname "$1")
  grep -o '](\([^)#]*\)' "$1" | sed 's/^](//' | grep -v '^http' | while IFS= read -r target; do
    if [ -n "$target" ] && [ ! -e "$dir/$target" ]; then printf '%s\n' "$target"; fi
  done
}

check "SKILL.md keeps the After compaction block" "$(grep -c '^## After compaction$' "$SDD")" "1"
check "SKILL.md links ledger.md from the After compaction block" \
  "$(awk '/^## After compaction$/ { on = 1; next } /^## / { on = 0 } on' "$SDD" | grep -c 'references/ledger\.md')" "1"
check "SKILL.md: every relative link resolves" "$(broken_links "$SDD")" ""

for topic in batching budget example-workflow finish-rulings ledger process-graph rationale rationalizations ruling-seat setup; do
  ref="$SDD_DIR/references/$topic.md"
  check "references/$topic.md exists and is not empty" "$([ -s "$ref" ] && echo yes || echo no)" "yes"
  check "SKILL.md links $topic.md with a Read line" \
    "$(grep -cE "^Read \[$topic\.md\]\(references/$topic\.md\) before you " "$SDD")" "1"
  check "references/$topic.md: every relative link resolves" "$(broken_links "$ref")" ""
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
