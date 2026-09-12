#!/usr/bin/env bash
# Inline mode is a document, and the claims that make it work are structural:
# which scripts it calls, which references it links, which ledger lines it
# shares with subagent mode, and which ruling-seat kinds it claims. A model is
# not needed to check any of them, so they are checked here instead of in a
# review.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
INLINE="$P/skills/executing-plans/SKILL.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
FINAL="$P/reference/final-review.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

for f in "$INLINE" "$SDD" "$FINAL"; do
  check "exists: $(basename "$(dirname "$f")")/$(basename "$f")" \
    "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# The scripts inline mode must call. Reading the plan directly would skip
# amendments; skipping next-step would end a session without a next action.
for s in 'task-brief --header' 'task-brief PLAN_FILE N' 'sdd-workspace' 'context-size' 'next-step' 'plan-amend'; do
  present "calls $s" "$INLINE" "$s"
done

# The two skills a finished or interrupted run hands control to. Dropping
# either would strand a session with nowhere to go.
present "names handoff" "$INLINE" "dr-superpowers:handoff"
present "names finishing" "$INLINE" "dr-superpowers:finishing-a-development-branch"

# Only the first 5,000 tokens of a skill body come back after compaction, so
# the recovery instructions have to be at the top.
check "opens with After compaction" \
  "$(grep -m 1 '^## ' "$INLINE")" "## After compaction"

# Links, and the files they point at.
present "links the shared final review" "$INLINE" "../../reference/final-review.md"
present "links the ruling prompt" "$INLINE" "../subagent-driven-development/references/ruling-prompt.md"
check "the shared final review exists" \
  "$([ -f "$P/reference/final-review.md" ] && echo yes || echo no)" "yes"
check "the ruling prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/ruling-prompt.md" ] && echo yes || echo no)" "yes"

# The mode is chosen by the plan, not by whether subagents exist.
absent "drops the upstream subagent-availability note" "$INLINE" \
  "works much better with access to subagents"

# The three ruling-seat kinds this mode can reach, and the five it cannot.
for k in blocked-plan plan-conflict final-residual; do
  present "claims the $k kind" "$INLINE" "\`$k\`"
done
# The skill names all eight kinds - three it runs and five it explains away -
# so "states the three and no others" is not greppable. Assert the three plus
# the sentence that excludes the rest.
present "names the kinds it does not run" "$INLINE" "no task reviewer"

# The fix cap, and the escalation clause both skills key on.
present "states the fix cap" "$INLINE" "fix round R/3"
present "inline writes the escalation clause" "$INLINE" "escalated inline -> subagent"
present "subagent mode reads the escalation clause" "$SDD" "escalated inline -> subagent"

# One ledger grammar for both modes.
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD" "$line"
done
present "inline marks an unreviewed completion" "$INLINE" "unreviewed"
present "inline assigns itself" "$INLINE" "implementer inline"

# The final review lives in one place now.
present "subagent mode links the shared final review" "$SDD" "final-review.md"
absent "subagent mode no longer spells out the package call" "$SDD" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
absent "inline mode does not spell out the package call" "$INLINE" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference spells out the package call" "$FINAL" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference names both modes" "$FINAL" "Inline mode"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
