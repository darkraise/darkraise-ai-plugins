#!/usr/bin/env bash
# The gates manifest is a format that adopting projects depend on, and the
# skill is the only specification of it. These checks pin the parts two
# sessions could otherwise read differently: the field set, the evidence
# values, the default, and the retry rule.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/running-gates/SKILL.md"

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

check "exists: skills/running-gates/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

present "gates names the manifest path" "$SKILL" 'docs/superpowers/gates.md'

# Two required fields and seven optional ones.
for f in Command Green; do
  present "required field $f" "$SKILL" "**\`$f\`**"
done
for f in Applies Evidence Repo Setup Teardown Known-flaky Why; do
  present "optional field $f" "$SKILL" "**\`$f\`**"
done
present "gates says seven optional fields" "$SKILL" 'Optional, seven of them'

# The four evidence values and the default. Defaulting to exit would make every
# Green line decorative in a manifest that omits the field.
for v in output exit image judgment; do
  present "evidence value $v" "$SKILL" "\`$v\`"
done
present "evidence default is output" "$SKILL" 'default is `output`'
present "output evidence needs the Green text" "$SKILL" 'The declared `Green` text appears in this run'
present "every gate also requires exit 0" "$SKILL" 'requires its command to exit 0'

# Branch-level only. A pointer from verification-before-completion would reach
# all sixteen implementer agents.
present "gates are branch level" "$SKILL" 'branch level'

# The rules that stop a rotted or flaky manifest passing silently.
present "stop at the first red" "$SKILL" 'first red'
present "known-flaky retries only its own failure" "$SKILL" 'matches the `Known-flaky`'
present "a non-launching gate is a manifest defect" "$SKILL" 'manifest defect'
present "gates computes its own base" "$SKILL" 'merge-base'
present "gates states a skip" "$SKILL" 'silent skip'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
