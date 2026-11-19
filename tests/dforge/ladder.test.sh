#!/usr/bin/env bash
# The execution floor table is data plan-lint reads at runtime, so its
# integrity is checkable without a model.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../../plugins/dforge/reference/ladder.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# block <tag> - print the body of the fenced block opened by ```<tag>
block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

assignment=$(block assignment)
check "the floor table has 9 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "9"

# Rule S caps a compliant Claude total at 8: reducible <= 5 plus risk 3. A row
# above it would mean the split gate is bypassable by scoring.
above=$(printf '%s\n' "$assignment" | awk 'NF && $1 > 8 {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "the floor table has no row above score 8" "${above:-NONE}" "NONE"

check "the floor table rows" "$(printf '%s\n' "$assignment" | tr '\n' ',')" \
  "0 sonnet low,1 sonnet low,2 sonnet low,3 sonnet medium,4 sonnet medium,5 sonnet high,6 opus high,7 opus high,8 opus high,"

bad=NONE
while read -r score model effort; do
  [ -n "$score" ] || continue
  case "$model" in sonnet|opus) ;; *) bad="model:$score:$model" ;; esac
  case "$effort" in low|medium|high) ;; *) bad="effort:$score:$effort" ;; esac
done <<< "$assignment"
check "every row names a model and an effort" "$bad" "NONE"

missing=NONE
for s in 0 1 2 3 4 5 6 7 8; do
  printf '%s\n' "$assignment" | awk -v s="$s" '$1 == s { f = 1 } END { exit !f }' || missing="$s"
done
check "the floor table covers every score 0 through 8" "$missing" "NONE"

for tag in escalation reserve retired; do
  check "no $tag block remains" "$(block "$tag" | grep -c .)" "0"
done

check "the codex judge block has two rows" "$(block codex-judge | grep -c .)" "2"
check "the agy judge block has two rows" "$(block agy-judge | grep -c .)" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
