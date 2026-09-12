#!/usr/bin/env bash
# Criteria files are data that skills hand to a judge subagent, so their shape
# is checkable without a model. Two things matter and both are structural: the
# ground-truth note the judge sees on every evaluation, and criterion ids that
# stay stable when a heading is reworded.
#
# The 2-to-4 bound is not style. One broad criterion is what fine-grained
# scoring replaces; five narrow ones start measuring the same thing twice.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRITERIA="$HERE/../criteria"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

check "criteria directory exists" \
  "$([ -d "$CRITERIA" ] && echo yes || echo no)" "yes"
check "TEMPLATE.md exists" \
  "$([ -f "$CRITERIA/TEMPLATE.md" ] && echo yes || echo no)" "yes"

for f in "$CRITERIA"/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)

  check "$base: has a ground truth note" \
    "$(grep -c '^## Ground Truth Note$' "$f")" "1"
  check "$base: has a criteria section" \
    "$(grep -c '^## Criteria$' "$f")" "1"

  headings=$(grep -c '^### ' "$f")
  in_range=$([ "$headings" -ge 2 ] && [ "$headings" -le 4 ] && echo ok || echo "count:$headings")
  check "$base: has 2 to 4 criteria" "$in_range" "ok"

  # Every criterion pins an id in braces so rewording the heading never changes
  # the id a skill or a report refers to.
  pinned=$(grep -c '^### .*{#[a-z0-9_]\{1,\}}$' "$f")
  check "$base: every criterion pins a slug-safe id" "$pinned" "$headings"

  ids=$(grep -o '{#[a-z0-9_]\{1,\}}' "$f" | LC_ALL=C sort)
  uniq_ids=$(printf '%s\n' "$ids" | LC_ALL=C sort -u)
  check "$base: criterion ids are unique" \
    "$(printf '%s\n' "$ids" | grep -c .)" "$(printf '%s\n' "$uniq_ids" | grep -c .)"

  # grep -P is unavailable here; awk with an octal byte range is portable.
  check "$base: content is ASCII only" \
    "$(LC_ALL=C awk '/[\200-\377]/{n++} END{print n+0}' "$f")" "0"
done

# task-review.md is named by subagent-driven-development, so its ids are a contract.
TR="$CRITERIA/task-review.md"
if [ -f "$TR" ]; then
  got=$(grep -o '{#[a-z0-9_]\{1,\}}' "$TR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "task-review exposes the four contracted ids" "$got" "quality scope spec verification"
fi

# The Codex review seat returns the same criteria through a JSON schema. Its
# integer score fields must be exactly task-review.md's ids, or that seat scores
# a different rubric from the judges it is averaged with.
SCHEMA="$CRITERIA/codex-review-schema.json"
check "codex-review-schema.json exists" "$([ -f "$SCHEMA" ] && echo yes || echo no)" "yes"
if [ -f "$SCHEMA" ] && [ -f "$TR" ]; then
  want=$(grep -o '{#[a-z0-9_]\{1,\}}' "$TR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  got=$(jq -r '.properties | to_entries[] | select(.value.type=="integer") | .key' "$SCHEMA" \
    | tr -d '\r' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "codex review schema scores exactly the task-review ids" "$got" "$want"
  # Strict structured output rejects a schema whose required list omits a key.
  check "codex review schema requires every property" \
    "$(jq -r '((.properties|keys)-(.required))|join(",")' "$SCHEMA" | tr -d '\r')" ""
  check "codex review findings items are strict" \
    "$(jq -r '.properties.findings.items | (.additionalProperties == false) and ((((.properties|keys)-(.required))|length) == 0)' "$SCHEMA" | tr -d '\r')" "true"
fi

# plan-review.md is named by writing-plans, so its ids are a contract.
PR="$CRITERIA/plan-review.md"
check "plan-review.md exists" "$([ -f "$PR" ] && echo yes || echo no)" "yes"
if [ -f "$PR" ]; then
  got=$(grep -o '{#[a-z0-9_]\{1,\}}' "$PR" | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
  check "plan-review exposes the four contracted ids" "$got" "assumptions coherence coverage executability"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
